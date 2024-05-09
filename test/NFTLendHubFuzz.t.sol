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
        lendHub = new NFTLendHub(address(usdc), 500, 3); // 5% interest, max 3 lendings
        // transfer some usdc to lendHub
        usdc.approve(address(lendHub), type(uint256).max);
        usdc.transfer(address(lendHub), 10_000 ether);
        // mint 1 nft to address(1). tokenID = 0
        nft.safeMint(address(1), "ipfs://QmUjkSSzaurpoWwkLUfp5QiHueCkPzhwvcHt4v2CsE1aoe");
    }

    // initiateLoan() fuzz tests

    function testFuzz_InitiateLoan(uint256 amount) public {
        amount = bound(amount, 1, 7 ether);
        uint256 durationHours = 24;
        vm.startPrank(address(1));
        uint256 tokenId = 0;
        nft.approve(address(lendHub), tokenId);
        uint256 txId = lendHub.initiateLoan(address(nft), tokenId, amount, durationHours);
        assertTrue(lendHub.getTransactionStatus(txId));
        vm.stopPrank();
    }

    //  repayLoan() fuzz tests

    function testFuzz_RepayLoan(uint256 amount) public {
        amount = bound(amount, 1, 7 ether);
        uint256 durationHours = 24;
        uint256 tokenId = 0;
        vm.startPrank(address(1));
        // initiate the loan
        nft.approve(address(lendHub), tokenId);
        uint256 txId = lendHub.initiateLoan(address(nft), tokenId, amount, durationHours);
        assertTrue(lendHub.getTransactionStatus(txId));
        // repay the loan
        uint256 totalDue = lendHub.getTotalAmountToPay(txId);
        usdc.approve(address(lendHub), totalDue);
        lendHub.repayLoan(txId, totalDue);
        // Check that the transaction is no longer active
        assertFalse(lendHub.getTransactionStatus(txId));
        // check that the NFT is returned to the borrower
        assertTrue(nft.ownerOf(tokenId) == address(1));
        vm.stopPrank();
    }

    // ERC721 Receiver implementation
    function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
