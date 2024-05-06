import { ethers } from "ethers";
import dotenv from "dotenv";

import abi_MockNFT from "../abi/contracts/MockNFT.sol/MockNFT.json";

// Load environment variables from .env file
dotenv.config();

// Interface for the expected structure of NFT metadata
interface NFTAttribute {
  trait_type: string;
  value: string;
}

interface NFTMetadata {
  name: string;
  description: string;
  image: string;
  strength: number;
  attributes: NFTAttribute[];
}

/**
 * Function to fetch NFT metadata from a blockchain
 */
async function getNFTMetadata() {
  const { PRIVATE_KEY, API_KEY_INFURA } = process.env;

  if (!PRIVATE_KEY || !API_KEY_INFURA) {
    console.error("Please ensure your .env file includes PRIVATE_KEY and API_KEY_INFURA.");
    return;
  }

  const SEPOLIA_URL = `https://sepolia.infura.io/v3/${API_KEY_INFURA}`;
  const provider = new ethers.JsonRpcProvider(SEPOLIA_URL);
  const wallet = new ethers.Wallet(PRIVATE_KEY, provider);

  const mockNFTAddress = "0x5487bEd72b079Fbd8384314D5eA11eD5ACB3F965";
  const tokenId = 0;

  const mockNFT = new ethers.Contract(mockNFTAddress, abi_MockNFT, wallet);
  try {
    console.log("Token ID:\n", tokenId);
    
    const result = await mockNFT.tokenURI(tokenId);
    const ipfsURL = addIPFSProxy(result);
    console.log("IPFS URL\n", ipfsURL);

    const response = await fetch(ipfsURL);
    const metadata: NFTMetadata = await response.json();
    console.log("NFT Metadata\n", metadata);

    if (metadata.image) {
      const image = addIPFSProxy(metadata.image);
      console.log("NFT Image URL\n", image);
    }
  } catch (error) {
    console.error("Failed to fetch NFT metadata:", error);
  }
}

// Function to convert an IPFS hash to a URL using a public gateway
function addIPFSProxy(ipfsHash: string): string {
    const URL = "https://ipfs.io/ipfs/";
    const hash = ipfsHash.replace(/^ipfs?:\/\//, "");
    return URL + hash;
  }
  
  getNFTMetadata();
