// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25 <0.9.0;

import { Test } from "forge-std/src/Test.sol";
import { console2 } from "forge-std/src/console2.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import { NFTLendHub } from "../src/NFTLendHub.sol";
import { MockNFT } from "../src/MockNFT.sol";
import { MockUSDC } from "../src/MockUSDC.sol";

contract NFTLendHubTest is Test, IERC721Receiver {
    NFTLendHub lendHub;
    MockNFT nft;
    MockUSDC usdc;

    function setUp() public {
        usdc = new MockUSDC(address(this));
        nft = new MockNFT(address(this));
        lendHub = new NFTLendHub(address(usdc), 500, 3); // 5% interest (basis ponits), max 3 lendings
        // transfer some usdc to lendHub
        usdc.approve(address(lendHub), type(uint256).max);
        usdc.transfer(address(lendHub), 1000 ether);
        // mint 1 nft to address(1). tokenID = 0
        nft.safeMint(address(1), "ipfs://QmUjkSSzaurpoWwkLUfp5QiHueCkPzhwvcHt4v2CsE1aoe");
    }

    // initiateLoan() tests

    function testInitiateLoan_Success() public {
        uint256 tokenId = 0;
        uint256 amountLend = 5 ether;
        uint256 durationHours = 24;
        vm.startPrank(address(1));
        nft.approve(address(lendHub), tokenId);
        uint256 txId = lendHub.initiateLoan(address(nft), tokenId, amountLend, durationHours);
        assertTrue(lendHub.getTransactionStatus(txId));
        vm.stopPrank();
    }

    function testInitiateLoan_FailDueToLoanLimit() public {
        // mint 4 nft to address(1), Ids 1 to 4, and approve lendHub to use them.
        for (uint256 i = 1; i < 5; i++) {
            nft.safeMint(address(1), "ipfs://QmUjkSSzaurpoWwkLUfp5QiHueCkPzhwvcHt4v2CsE1aoe");
            vm.prank(address(1));
            nft.approve(address(lendHub), i);
        }
        uint256 amountLend = 5 ether;
        uint256 durationHours = 24;
        vm.startPrank(address(1));
        lendHub.initiateLoan(address(nft), 1, amountLend, durationHours);
        lendHub.initiateLoan(address(nft), 2, amountLend, durationHours);
        lendHub.initiateLoan(address(nft), 3, amountLend, durationHours);
        vm.expectRevert(abi.encodeWithSelector(NFTLendHub.LoanLimitExceeded.selector,3 ));
        // vm.expectRevert(lendHub.LoanLimitExceeded.selector);
        lendHub.initiateLoan(address(nft), 4, amountLend, durationHours);
        vm.stopPrank();
    }

    function testInitiateLoan_FailDueToNonOwnership() public {
        uint256 tokenId = 0;
        uint256 amountLend = 5 ether;
        uint256 durationHours = 24;
        // Address 1 approves lendHub to use the NFT
        vm.prank(address(1));
        nft.approve(address(lendHub), tokenId);
        // Address 2 attempts to initiate the loan
        vm.prank(address(2));
        vm.expectRevert(NFTLendHub.NotNftOwner.selector);
        lendHub.initiateLoan(address(nft), tokenId, amountLend, durationHours);
    }

    function testInitiateLoan_FailDueToExcessiveDuration() public {
        uint256 tokenId = 0;
        uint256 amountLend = 5 ether;
        vm.startPrank(address(1));
        nft.approve(address(lendHub), tokenId);
        uint256 excessiveDuration = lendHub.MAX_HOURS_FOR_LOAN() + 1;
        vm.expectRevert(NFTLendHub.LoanDurationExceeded.selector);
        lendHub.initiateLoan(address(nft), tokenId, amountLend, excessiveDuration);
        vm.stopPrank();
    }

    // repayLoan()

    function testRepayLoan_Success() public {
        uint256 tokenId = 0;
        uint256 amountLent = 5 ether;
        uint256 durationHours = 24;

        vm.startPrank(address(1));
        // initiate the loan
        nft.approve(address(lendHub), tokenId);
        uint256 transactionId = lendHub.initiateLoan(address(nft), tokenId, amountLent, durationHours);
        assertTrue(lendHub.getTransactionStatus(transactionId));

        // Calculate the correct total amount to pay which includes some interest
        uint256 totalDue = lendHub.getTotalAmountToPay(transactionId);
        usdc.approve(address(lendHub), totalDue);
        lendHub.repayLoan(transactionId, totalDue);

        // Check that the transaction is no longer active
        assertFalse(lendHub.getTransactionStatus(transactionId));
        // check that the NFT is returned to the borrower
        assertTrue(nft.ownerOf(tokenId) == address(1));
        vm.stopPrank();
    }

    function testRepayLoan_FailDueToInsufficientAmount() public {
        uint256 tokenId = 0;
        uint256 amountLent = 5 ether;
        uint256 durationHours = 24;

        vm.startPrank(address(1));
        nft.approve(address(lendHub), tokenId);
        uint256 transactionId = lendHub.initiateLoan(address(nft), tokenId, amountLent, durationHours);
        assertTrue(lendHub.getTransactionStatus(transactionId));

        // Calculate the correct total amount to pay which includes some interest
        uint256 totalDue = lendHub.getTotalAmountToPay(transactionId);
        uint256 insufficientAmount = totalDue - 10; // Less than needed
        usdc.approve(address(lendHub), insufficientAmount);

        vm.expectRevert(NFTLendHub.InsufficientUserBalance.selector);
        lendHub.repayLoan(transactionId, insufficientAmount);
        vm.stopPrank();
    }

    function testRepayLoan_FailDueToWrongUser() public {
        uint256 tokenId = 0;
        uint256 amountLent = 5 ether;
        uint256 durationHours = 24;

        vm.startPrank(address(1));
        nft.approve(address(lendHub), tokenId);
        uint256 transactionId = lendHub.initiateLoan(address(nft), tokenId, amountLent, durationHours);
        assertTrue(lendHub.getTransactionStatus(transactionId));

        // Calculate the correct total amount to pay which includes some interest
        uint256 totalDue = lendHub.getTotalAmountToPay(transactionId);
        usdc.approve(address(lendHub), totalDue);
        vm.stopPrank();

        // Address 2 tries to repay the loan
        vm.prank(address(2));
        vm.expectRevert(NFTLendHub.NotBorrower.selector);
        lendHub.repayLoan(transactionId, totalDue);
    }

    // ERC721 Receiver implementation
    function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
