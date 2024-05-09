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
    address immutable owner;
    uint16 private interestRate; // annual interest rate in basis points
    MockUSDC public immutable usdcToken;

    uint16 private immutable maxNumberOfLendings;
    uint16 public constant MAX_HOURS_FOR_LOAN = 720; // 30 days in hours
    uint256 private constant BASIS_POINTS = 10_000;
    uint256 private constant HOURS_PER_YEAR = 8760; // Average hours in a year, considering leap years might adjust
        // slightly

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

    // Events
    event LoanInitiated(address user, uint256 amount, uint256 timeLimit, uint256 transactionID);
    event LoanRepaid(address user, uint256 totalAmountPaid);
    event DefaultedNftProcessed(
        uint256 transactionId, uint256 nftMarketPrice, uint256 totalDebt, uint256 refundToBorrower
    );

    // Errors
    error NotOwner();
    error NotNftOwner();
    error NotBorrower();
    error ZeroAddress();
    error UnauthorizedTransfer();
    error UsdcTransferFailed();
    error InvalidTransactionId();
    error InvalidLoanAmount(string message);
    error InsufficientUserBalance();
    error InsufficientContractFunds();
    error LoanLimitExceeded(uint256 maxNumberOfLendings);
    error LoanDurationExceeded();
    error LoanNotYetDefaulted();
    error LoanInactiveOrExpired();

    // Modifiers
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier validTransactionId(uint256 transactionId) {
        if (transactionId <= 0 || transactionId >= nextTransactionId) revert InvalidTransactionId();
        _;
    }

    modifier loanLimitNotExceeded(address user) {
        if (loanCountByUser[user] >= maxNumberOfLendings) revert LoanLimitExceeded(maxNumberOfLendings);
        _;
    }

    modifier activeLoan(uint256 transactionId) {
        LendingTransaction storage transaction = transactionIdToLendingDetails[transactionId];
        if (!transaction.isActive || transaction.endTime < block.timestamp) revert LoanInactiveOrExpired();
        _;
    }

    // Functions

    constructor(address usdcAddress, uint16 initialInterestRate, uint8 maxLendings) {
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

        if (msg.sender == address(0)) revert ZeroAddress();
        if (msg.sender != nft.ownerOf(tokenId)) revert NotNftOwner();

        if (amountLend <= 0) revert InvalidLoanAmount("Loan amount must be greater than zero");
        if (amountLend > usdcToken.balanceOf(address(this))) revert InsufficientContractFunds();

        if (nft.getApproved(tokenId) != address(this)) revert UnauthorizedTransfer();
        if (durationHours > MAX_HOURS_FOR_LOAN) revert LoanDurationExceeded();

        uint256 nftPrice = getNftPrice();
        if (amountLend > nftPrice * 70 / 100) revert InvalidLoanAmount("Loan amount exceeds 70% of NFT value");

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
        if (!success) revert UsdcTransferFailed();

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
        if (msg.sender != transactionIdToLendingDetails[transactionId].user) revert NotBorrower();

        uint256 totalAmountToPay = getTotalAmountToPay(transactionId);
        if (amount < totalAmountToPay) revert InsufficientUserBalance();

        loanCountByUser[msg.sender]--;

        _completeLoanRepayment(transactionId, amount);
    }

    /**
     * @dev Internal function to handle the transfer of USDC and return of NFT.
     * @param transactionId The ID of the transaction for which funds and NFT are being transferred.
     * @param amount The total amount being transferred by the borrower.
     */
    function _completeLoanRepayment(uint256 transactionId, uint256 amount) internal {
        LendingTransaction storage transaction = transactionIdToLendingDetails[transactionId];

        transaction.isActive = false;
        // approve the transfer of USDC from the borrower to the contract
        bool success = usdcToken.transferFrom(msg.sender, address(this), amount);
        if (!success) revert UsdcTransferFailed();

        IERC721(transaction.nftAddress).transferFrom(address(this), msg.sender, transaction.tokenId);

        emit LoanRepaid(msg.sender, amount);
    }

    /**
     * @notice Sells the NFT collateral if the loan defaults, transferring the NFT to the contract owner and paying off
     * the debt from the sale proceeds.
     * @param transactionId The ID of the defaulted loan transaction.
     */
    function liquidateCollateralOnDefault(uint256 transactionId) public validTransactionId(transactionId) {
        LendingTransaction storage transaction = transactionIdToLendingDetails[transactionId];

        if (!transaction.isActive) revert LoanInactiveOrExpired();
        if (transaction.endTime > block.timestamp) revert LoanNotYetDefaulted();

        uint256 nftMarketPrice = getNftPrice();

        // Decrement the loan count for the user
        loanCountByUser[transaction.user]--;

        // Perform the transfer of USDC and NFT
        _handleDefaultedAssetTransfer(transactionId, nftMarketPrice);
    }

    /**
     * @dev Handles the transfer of USDC from the owner to the contract and the NFT from the contract to the owner.
     * @param transactionId The ID of the transaction related to the defaulted loan.
     * @param nftMarketPrice The market price of the NFT obtained, simulating an oracle call.
     */
    function _handleDefaultedAssetTransfer(uint256 transactionId, uint256 nftMarketPrice) internal {
        LendingTransaction storage transaction = transactionIdToLendingDetails[transactionId];

        // Checks
        if (nftMarketPrice > usdcToken.balanceOf(owner)) revert InsufficientUserBalance();

        // Effects
        uint256 totalDebt = getTotalAmountToPay(transactionId);
        uint256 refundToBorrower = nftMarketPrice > totalDebt ? nftMarketPrice - totalDebt : 0;
        transaction.isActive = false; // Update the loan status before external interactions

        // Interactions
        bool usdcTransferSuccess = usdcToken.transferFrom(owner, address(this), nftMarketPrice);
        if (!usdcTransferSuccess) revert UsdcTransferFailed();

        IERC721(transaction.nftAddress).transferFrom(address(this), owner, transaction.tokenId);

        if (refundToBorrower > 0) {
            bool refundSuccess = usdcToken.transfer(transaction.user, refundToBorrower);
            if (!refundSuccess) revert UsdcTransferFailed(); // Ensure the transfer is successful
        }

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
        return transactionIdToLendingDetails[transactionId].amountLent + getInterest(transactionId);
    }

    /**
     * @notice Retrieves the interest amount of a specific transaction.
     * @param transactionId The ID of the transaction to retrieve the interest amount for.
     * @return interestAmount The interest amount of the transaction.
     */
    function getInterest(uint256 transactionId) public view validTransactionId(transactionId) returns (uint256) {
        // get time elapsed in hours
        uint256 timeElapsedInHours = getTransactionTime(transactionId) / 1 hours;

        // Convert the annual interest rate from basis points to a per-hour rate
        uint256 hourlyInterestRate = (interestRate * timeElapsedInHours) / (BASIS_POINTS * HOURS_PER_YEAR);

        // Calculate the interest based on the time elapsed
        // Adjust for basis points to get the final interest amount
        uint256 interest = (getPricipalAmount(transactionId) * hourlyInterestRate) / BASIS_POINTS;
        return interest;
    }

    /**
     * @notice Retrieves the principal amount of a specific transaction.
     * @param transactionId The ID of the transaction to retrieve the principal amount for.
     * @return principalAmount The principal amount of the transaction.
     */
    function getPricipalAmount(uint256 transactionId) public view validTransactionId(transactionId) returns (uint256) {
        return transactionIdToLendingDetails[transactionId].amountLent;
    }

    /// @notice Calculates the time spent on a specific transaction.
    /// @param transactionId The ID of the transaction to calculate for.
    /// @return timeSpent The time spent on the transaction in hours
    function getTransactionTime(uint256 transactionId)
        public
        view
        validTransactionId(transactionId)
        returns (uint256)
    {
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
    function changeInterestRate(uint8 _newInterestRate) public onlyOwner {
        interestRate = _newInterestRate;
    }

    // ERC721 Receiver implementation
    function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
