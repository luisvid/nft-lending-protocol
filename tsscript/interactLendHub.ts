import { ethers } from "ethers";
import dotenv from "dotenv";

// Import ABIs for the contracts to interact with
import abi_LendHub from "../abi/contracts/NFTLendHub.sol/NFTLendHub.json";
import abi_MockNFT from "../abi/contracts/MockNFT.sol/MockNFT.json";
import abi_USDC from "../abi/contracts/MockUSDC.sol/MockUSDC.json";
import { log } from "console";

dotenv.config();

interface LoanInitiatedEventArgs {
    user: string;
    amount: ethers.BigNumberish;
    timeLimit: ethers.BigNumberish;
    transactionID: ethers.BigNumberish;
}

interface CustomEvent {
    event?: string;
    args?: any;
  }

/**
 * This function interacts with the NFTLendHub, MockNFT, and MockUSDC contracts on the Sepolia network.
 * It performs a series of blockchain transactions including approving and transferring USDC, minting NFTs,
 * and initiating a loan using an NFT as collateral.
 */
async function initiateLoan() {
  const { PRIVATE_KEY, API_KEY_INFURA } = process.env;

  if (!PRIVATE_KEY || !API_KEY_INFURA) {
    console.error("Please ensure your .env file includes PRIVATE_KEY and API_KEY_INFURA.");
    return;
  }

  const SEPOLIA_URL = `https://sepolia.infura.io/v3/${API_KEY_INFURA}`;
  const provider = new ethers.JsonRpcProvider(SEPOLIA_URL);
  const wallet = new ethers.Wallet(PRIVATE_KEY, provider);

  //   contract addresses deployed on Sepolia network
  const nftLendHubAddress = "0xE08EccbB24F2c28d5Cf7bd8633062Fe106bcA586";
  const mockNFTAddress = "0x5487bEd72b079Fbd8384314D5eA11eD5ACB3F965";
  const mockUSDCAddress = "0xe9f6A331564FdB02eEdD4A418E54BA61cfadda1c";

  // Set up contract instances
  const nftLendHub = new ethers.Contract(nftLendHubAddress, abi_LendHub, wallet);
  const mockNFT = new ethers.Contract(mockNFTAddress, abi_MockNFT, wallet);
  const mockUSDC = new ethers.Contract(mockUSDCAddress, abi_USDC, wallet);

  try {
    // Approve unlimited USDC for the NFTLendHub to use
    log("Approving USDC for lending");
    const approvalTx = await mockUSDC.approve(nftLendHubAddress, ethers.MaxUint256);
    await approvalTx.wait();
    console.log(`USDC approved for lending; transaction hash: ${approvalTx.hash}`);

    // Transfer 1000 USDC to NFTLendHub to fund it for lending operations
    log("Transferring USDC to NFTLendHub");
    const transferTx = await mockUSDC.transfer(nftLendHubAddress, ethers.parseUnits("1000", 18)); 
    await transferTx.wait();
    const usdcBalance = await mockUSDC.balanceOf(nftLendHubAddress);
    console.log(`NFTLendHub contract now has a balance of ${ethers.formatUnits(usdcBalance, 18)} USDC`);

    // Mint a new NFT to the wallet address
    log("Minting NFT");
    const mintTx = await mockNFT.safeMint(wallet.address, "ipfs://QmUjkSSzaurpoWwkLUfp5QiHueCkPzhwvcHt4v2CsE1aoe");
    await mintTx.wait();
    console.log(`NFT minted successfully; transaction hash: ${mintTx.hash}`);
    
    // Get NFT price from the NFTLendHub, which is needed to calculate maximum loan value
    const nftPrice = await nftLendHub.getNftPrice();
    console.log(`Current NFT market price is ${ethers.formatEther(nftPrice)} ETH`);

    // Example token ID (assuming it's the first minted token, which has ID 0)
    const tokenId = 0;

    // Approve NFTLendHub to transfer the minted NFT
    log("Approving NFT for collateral use");
    const nftApprovalTx = await mockNFT.approve(nftLendHubAddress, tokenId);
    await nftApprovalTx.wait();
    console.log(`NFT approved for collateral use; transaction hash: ${nftApprovalTx.hash}`);

    // Initiate a loan using the NFT as collateral
    log("Initiating loan");
    const loanAmount = ethers.parseUnits("5", 18); // Loan amount in USDC
    const loanDuration = 24; // Loan duration in hours
    const initiateLoanTx = await nftLendHub.initiateLoan(mockNFTAddress, tokenId, loanAmount, loanDuration);
    const loanReceipt = await initiateLoanTx.wait();
    console.log(`Loan initiated successfully; transaction hash: ${loanReceipt.hash}`);
    
  } catch (error) {
    console.error("Blockchain interaction failed:", error);
  }
}

initiateLoan();
