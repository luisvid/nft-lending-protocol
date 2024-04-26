// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25 <0.9.0;

import { MockUSDC } from "../src/MockUSDC.sol";
import { MockNFT } from "../src/MockNFT.sol";
import { NFTLendHub } from "../src/NFTLendHub.sol";

import { BaseScript } from "./Base.s.sol";

import { console2 } from "forge-std/src/console2.sol";

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
contract Deploy is BaseScript {
    function run() public broadcast returns (MockUSDC mockUSDC, MockNFT mockNFT, NFTLendHub nftLendHub) {
        mockUSDC = new MockUSDC(broadcaster);
        console2.log("Deployed mockUSDC at:", address(mockUSDC));

        mockNFT = new MockNFT(broadcaster);
        console2.log("Deployed mockNFT at:", address(mockNFT));

        nftLendHub = new NFTLendHub(address(mockUSDC), 5, 3);
        console2.log("Deployed nftLendHub at:", address(nftLendHub));
    }
}

// execution command   
// forge script script/DeployNFTLendHub.s.sol --rpc-url sepolia --broadcast --verify -vvvv
