// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./MockUSDC.sol";

/**
 * @title NFT Collateral-based Lending Platform
 * @dev Allows users to lend USDC using NFTs as collateral. Interest accrues per hour.
 */
contract NFTLendHub is IERC721Receiver {
    uint8 private interestRate;
    uint8 private immutable maxNumberOfLendings;
    uint16 public constant MAX_HOURS_FOR_LOAN = 720; // 30 days in hours
    address immutable owner;
    MockUSDC public immutable usdcToken;

    //  Structure for storing a transaction
    struct LendingTransaction {
        address user; // The address of the user borrowing funds
        address nftAddress; // The address of the NFT contract
        uint256 tokenId; // The token ID of the NFT used as collateral
        uint256 amountLent; // The amount of funds lent to the user
        uint256 startTime; // Timestamp when the loan starts
        uint256 endTime; // Timestamp when the loan is due to be repaid
        bool isActive; // Flag to indicate if the loan is active
    }

    // Maps each unique transaction ID to the corresponding LendingTransaction details
    mapping(uint256 => LendingTransaction) private transactionIdToLendingDetails;
    // Tracks the number of active loans per user
    mapping(address => uint256) internal loanCountByUser;

    uint256 private nextTransactionId = 1;

    event LoanInitiated(address user, uint256 amount, uint256 timeLimit, uint256 transactionID);
    event LoanRepaid(address user, uint256 totalAmountPaid);
    event DefaultedNftProcessed(
        uint256 transactionId, uint256 nftMarketPrice, uint256 totalDebt, uint256 refundToBorrower
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not the owner");
        _;
    }

    modifier validTransactionId(uint256 transactionId) {
        require(transactionId > 0 && transactionId < nextTransactionId, "Invalid transaction ID");
        _;
    }

    modifier loanLimitNotExceeded(address user) {
        require(loanCountByUser[user] < maxNumberOfLendings, "Loan limit exceeded");
        _;
    }

    modifier activeLoan(uint256 transactionId) {
        LendingTransaction storage transaction = transactionIdToLendingDetails[transactionId];
        require(transaction.isActive && transaction.endTime >= block.timestamp, "Loan is inactive or expired");
        _;
    }

    constructor(address usdcAddress, uint8 initialInterestRate, uint8 maxLendings) {
        owner = msg.sender;
        usdcToken = MockUSDC(usdcAddress);
        interestRate = initialInterestRate;
        maxNumberOfLendings = maxLendings;
    }

    /**
     * @notice Initiates a new loan using an NFT as collateral.
     * @param nftAddress The address of the NFT contract.
     * @param tokenId The NFT token ID used as collateral.
     * @param amountLend The amount of USDC to lend.
     * @param durationHours The duration of the loan in hours.
     * @return transactionId The ID of the created lending transaction.
     */
    function initiateLoan(
        address nftAddress,
        uint256 tokenId,
        uint256 amountLend,
        uint256 durationHours
    )
        public
        loanLimitNotExceeded(msg.sender)
        returns (uint256)
    {
        // nft to be used as collateral
        IERC721 nft = IERC721(nftAddress);

        require(msg.sender != address(0), "Cannot lend to zero address");
        require(msg.sender == nft.ownerOf(tokenId), "Caller must own the NFT");
        // amountLend must be greater than 0
        require(amountLend > 0, "Amount to lend must be greater than 0");
        require(amountLend <= usdcToken.balanceOf(address(this)), "Insufficient funds in contract");
        require(nft.getApproved(tokenId) == address(this), "Contract must be approved to transfer NFT");
        require(durationHours <= MAX_HOURS_FOR_LOAN, "Loan duration exceeds maximum allowed");

        uint256 nftPrice = getNftPrice();
        require(amountLend <= nftPrice * 70 / 100, "Loan amount exceeds 70% of NFT value");

        LendingTransaction memory newTransaction = LendingTransaction({
            user: msg.sender,
            nftAddress: nftAddress,
            tokenId: tokenId,
            amountLent: amountLend,
            startTime: block.timestamp,
            endTime: block.timestamp + (durationHours * 1 hours),
            isActive: true
        });
        transactionIdToLendingDetails[nextTransactionId] = newTransaction;
        loanCountByUser[msg.sender]++;

        nft.safeTransferFrom(msg.sender, address(this), tokenId);

        bool success = usdcToken.transfer(msg.sender, amountLend);
        require(success, "USDC transfer failed");

        emit LoanInitiated(msg.sender, amountLend, durationHours, nextTransactionId);

        return nextTransactionId++;
    }

    /**
     * @notice Repays the loan and returns the NFT collateral to the borrower.
     * @param transactionId The ID of the transaction being repaid.
     * @param amount The amount being paid which should cover the loan and accrued interest.
     */
    function repayLoan(
        uint256 transactionId,
        uint256 amount
    )
        public
        validTransactionId(transactionId)
        activeLoan(transactionId)
    {
        require(msg.sender == transactionIdToLendingDetails[transactionId].user, "Only the borrower can repay the loan");

        uint256 totalAmountToPay = getTotalAmountToPay(transactionId);
        require(amount >= totalAmountToPay, "Insufficient amount to cover the loan and interest");

        _completeLoanRepayment(transactionId, amount);

        loanCountByUser[msg.sender]--;
    }

    /**
     * @dev Internal function to handle the transfer of USDC and return of NFT.
     * @param transactionId The ID of the transaction for which funds and NFT are being transferred.
     * @param amount The total amount being transferred by the borrower.
     */
    function _completeLoanRepayment(uint256 transactionId, uint256 amount) internal {
        LendingTransaction storage transaction = transactionIdToLendingDetails[transactionId];

        // approve the transfer of USDC from the borrower to the contract
        usdcToken.transferFrom(msg.sender, address(this), amount);

        if (transaction.isActive) {
            transaction.isActive = false;
            IERC721(transaction.nftAddress).transferFrom(address(this), msg.sender, transaction.tokenId);
        }

        emit LoanRepaid(msg.sender, amount);
    }

    /**
     * @notice Sells the NFT collateral if the loan defaults, transferring the NFT to the contract owner and paying off
     * the debt from the sale proceeds.
     * @param transactionId The ID of the defaulted loan transaction.
     */
    function liquidateCollateralOnDefault(uint256 transactionId) public {
        LendingTransaction storage transaction = transactionIdToLendingDetails[transactionId];

        require(transactionId > 0 && transactionId < nextTransactionId, "Invalid transaction ID");
        require(transaction.isActive, "Transaction is no longer active");
        require(transaction.endTime < block.timestamp, "Loan has not yet defaulted");

        uint256 nftMarketPrice = getNftPrice();

        // Perform the transfer of USDC and NFT
        _handleDefaultedAssetTransfer(transactionId, nftMarketPrice);

        // Decrement the loan count for the user
        loanCountByUser[transaction.user]--;
    }

    /**
     * @dev Handles the transfer of USDC from the owner to the contract and the NFT from the contract to the owner.
     * @param transactionId The ID of the transaction related to the defaulted loan.
     * @param nftMarketPrice The market price of the NFT obtained, simulating an oracle call.
     */
    function _handleDefaultedAssetTransfer(uint256 transactionId, uint256 nftMarketPrice) internal {
        LendingTransaction storage transaction = transactionIdToLendingDetails[transactionId];

        require(usdcToken.balanceOf(owner) >= nftMarketPrice, "Owner does not have enough USDC to buy the NFT");
        bool usdcTransferSuccess = usdcToken.transferFrom(owner, address(this), nftMarketPrice);
        require(usdcTransferSuccess, "Failed to transfer USDC from owner to contract");

        IERC721(transaction.nftAddress).transferFrom(address(this), owner, transaction.tokenId);

        uint256 totalDebt = getTotalAmountToPay(transactionId);
        uint256 refundToBorrower = nftMarketPrice > totalDebt ? nftMarketPrice - totalDebt : 0;

        if (refundToBorrower > 0) {
            usdcToken.transfer(transaction.user, refundToBorrower);
        }

        // Update the loan status
        transaction.isActive = false;

        emit DefaultedNftProcessed(transactionId, nftMarketPrice, totalDebt, refundToBorrower);
    }

    /**
     * @notice Calculates the total amount to be repaid for a specific transaction.
     * @param transactionId The ID of the transaction to calculate for.
     * @return totalAmount The total amount to be repaid, including interest.
     */
    function getTotalAmountToPay(uint256 transactionId)
        public
        view
        validTransactionId(transactionId)
        returns (uint256)
    {
        uint256 principalAmount = transactionIdToLendingDetails[transactionId].amountLent;
        uint256 interestAmount = getInterest(transactionId);
        return principalAmount + interestAmount;
    }

    /**
     * @notice Retrieves the principal amount of a specific transaction.
     * @param transactionId The ID of the transaction to retrieve the principal amount for.
     * @return principalAmount The principal amount of the transaction.
     */
    function getPricipalAmount(uint256 transactionId) public view validTransactionId(transactionId) returns (uint256) {
        return transactionIdToLendingDetails[transactionId].amountLent;
    }

    /**
     * @notice Retrieves the interest amount of a specific transaction.
     * @param transactionId The ID of the transaction to retrieve the interest amount for.
     * @return interestAmount The interest amount of the transaction.
     */
    function getInterest(uint256 transactionId) public view validTransactionId(transactionId) returns (uint256) {
        uint256 timeSpent = getTimeSpent(transactionId);
        uint256 interestAmount =
            transactionIdToLendingDetails[transactionId].amountLent * interestRate / 100 * timeSpent;

        return interestAmount;
    }

    /// @notice Calculates the time spent on a specific transaction.
    /// @param transactionId The ID of the transaction to calculate for.
    /// @return timeSpent The time spent on the transaction.
    function getTimeSpent(uint256 transactionId) public view validTransactionId(transactionId) returns (uint256) {
        if (block.timestamp < transactionIdToLendingDetails[transactionId].endTime) {
            return block.timestamp - transactionIdToLendingDetails[transactionId].startTime;
        } else {
            return transactionIdToLendingDetails[transactionId].endTime
                - transactionIdToLendingDetails[transactionId].startTime;
        }
    }

    /// @notice Returns the price of the NFT. Simulating a oracle call to get the price.
    function getNftPrice() public pure returns (uint256) {
        return 10 ether;
    }

    // Utility functions
    function convertToHours(uint256 timeToReturn) public pure returns (uint256) {
        return timeToReturn * 3600;
    }

    // Getters
    function getTransactionStatus(uint256 transactionId) public view validTransactionId(transactionId) returns (bool) {
        return transactionIdToLendingDetails[transactionId].isActive;
    }

    // Setters
    function changeInterestRate(uint8 _newInterestRate) public {
        require(msg.sender == owner, "Only owner can change interest rate");
        interestRate = _newInterestRate;
    }

    // ERC721 Receiver implementation
    function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
