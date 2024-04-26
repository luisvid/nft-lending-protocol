// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25 <0.9.0;

import { Test } from "forge-std/src/Test.sol";
import { console2 } from "forge-std/src/console2.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

// import "forge-std/Test.sol";
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
        lendHub = new NFTLendHub(address(usdc), 5, 3); // 5% interest, max 3 lendings
        // transfer some usdc to lendHub
        usdc.approve(address(lendHub), type(uint256).max);
        usdc.transfer(address(lendHub), 1000);
        // mint 5 nft to address(1).
        for (uint256 i = 0; i < 5; i++) {
            nft.safeMint(address(1), "https://example.com");
        }
    }

    // initiateLoan()

    function testInitiateLoan_Success() public {
        vm.startPrank(address(1));
        nft.approve(address(lendHub), 0);
        uint256 txId = lendHub.initiateLoan(address(nft), 0, 100, 24);
        assertTrue(lendHub.getTransactionStatus(txId));
        vm.stopPrank();
    }

    function testInitiateLoan_FailDueToLoanLimit() public {
        vm.startPrank(address(1));
        // approve nft id from 1 to 4 to lendHub
        for (uint256 i = 1; i < 5; i++) {
            nft.approve(address(lendHub), i);
        }
        lendHub.initiateLoan(address(nft), 1, 100, 24);
        lendHub.initiateLoan(address(nft), 2, 100, 24);
        lendHub.initiateLoan(address(nft), 3, 100, 24);
        vm.expectRevert("Loan limit exceeded");
        lendHub.initiateLoan(address(nft), 4, 100, 24);
        vm.stopPrank();
    }

    function testInitiateLoan_FailDueToNonOwnership() public {
        nft.safeMint(address(2), "https://example.com");
        uint256 tokenId = 5;
        // Address 2 approves lendHub to use the NFT
        vm.prank(address(2));
        nft.approve(address(lendHub), tokenId);
        // Address 1 attempts to initiate the loan
        vm.prank(address(1));
        vm.expectRevert("Caller must own the NFT");
        lendHub.initiateLoan(address(nft), tokenId, 50, 24);
    }

    function testInitiateLoan_FailDueToExcessiveDuration() public {
        nft.safeMint(address(1), "https://example.com");
        uint256 tokenId = 5;
        vm.startPrank(address(1));
        nft.approve(address(lendHub), tokenId);
        uint256 excessiveDuration = lendHub.MAX_HOURS_FOR_LOAN() + 1;
        vm.expectRevert("Loan duration exceeds maximum allowed");
        lendHub.initiateLoan(address(nft), tokenId, 100, excessiveDuration);
        vm.stopPrank();
    }

    // repayLoan()

    function testRepayLoan_Success() public {
        nft.safeMint(address(1), "https://example.com");
        uint256 tokenId = 5;
        uint256 amountLent = 100;
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
        nft.safeMint(address(1), "https://example.com");
        uint256 tokenId = 5;
        uint256 amountLent = 100;
        uint256 durationHours = 24;

        vm.startPrank(address(1));
        nft.approve(address(lendHub), tokenId);
        uint256 transactionId = lendHub.initiateLoan(address(nft), tokenId, amountLent, durationHours);
        assertTrue(lendHub.getTransactionStatus(transactionId));

        // Calculate the correct total amount to pay which includes some interest
        uint256 totalDue = lendHub.getTotalAmountToPay(transactionId);
        uint256 insufficientAmount = totalDue - 10; // Less than needed
        usdc.approve(address(lendHub), insufficientAmount);

        vm.expectRevert("Insufficient amount to cover the loan and interest");
        lendHub.repayLoan(transactionId, insufficientAmount);
        vm.stopPrank();
    }

    // Generate the test cases for the following functions:
    // testRepayLoan_Success: Verifies successful loan repayment and return of the NFT.
    // testRepayLoan_FailDueToWrongUser: Tries to repay the loan by a user who isn't the borrower.

    function testRepayLoan_FailDueToWrongUser() public {
        nft.safeMint(address(1), "https://example.com");
        uint256 tokenId = 5;
        uint256 amountLent = 100;
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
        vm.expectRevert("Only the borrower can repay the loan");
        lendHub.repayLoan(transactionId, totalDue);
    }


    // ERC721 Receiver implementation
    function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
