# NFTLendHub Contract Documentation

The NFTLendHub contract is designed to facilitate a lending platform where NFTs are used as collateral for borrowing a
mock USDC token. This proof of concept (PoC) aims to demonstrate how blockchain technology can be used for decentralized
finance (DeFi) applications related to NFTs.

## Features of the NFTLendHub Contract

1. **Initiate Loan**

   - **Functionality:** Users can initiate a loan by providing an NFT as collateral. The loan amount must not exceed 70%
     of the NFT's appraised value.
   - **Parameters:**
     - `nftAddress`: Address of the NFT contract.
     - `tokenId`: Token ID of the NFT used as collateral.
     - `amountLend`: Amount of USDC to be lent.
     - `durationHours`: Duration of the loan in hours.
   - **Constraints:** The loan duration cannot exceed 720 hours (30 days), and the user must own the NFT and approve the
     contract to manage it.

2. **Repay Loan**

   - **Functionality:** Allows users to repay their loans in full, including accrued interest, to reclaim their NFT
     collateral.
   - **Parameters:**
     - `transactionId`: ID of the lending transaction.
     - `amount`: Total amount being paid to cover the loan and interest.
   - **Requirements:** Only the borrower can initiate repayment, and the repayment amount must cover the total debt
     including interest.

3. **Liquidate Collateral on Default**

   - **Functionality:** If a loan is not repaid by the due time, the contract owner can liquidate the NFT to recover the
     borrowed amount.
   - **Parameters:**
     - `transactionId`: ID of the defaulted loan transaction.
   - **Process:** The NFT is sold at its market price, any excess after covering the debt is refunded to the borrower.

4. **Interest Calculation**

   - **Functionality:** Calculates the interest based on the loan amount and the time elapsed since the loan initiation.
   - **Method:** Interest is computed as a simple interest with the rate determined at the loan initiation.

5. **Transaction Management**
   - **Functionality:** Tracks all loan transactions, ensuring unique IDs for each and maintaining details such as loan
     amount, start and end time, and collateral details.

### Getting Started

To successfully deploy and interact with the NFTLendHub, you will need the following:

- **MetaMask Wallet**: Ensure you have a MetaMask wallet loaded with testnet ETH for transactions on Ethereum test
  networks.
- **Infura Account and API Key**: Obtain an Infura account and API key to access Ethereum networks and manage
  deployments and interactions with smart contracts.
- **Diligence Fuzzing Account and API Key**: Secure a Diligence Fuzzing account and API key for advanced fuzzing
  testing, which helps in identifying vulnerabilities in smart contracts.
- **Contract Deployment Tools**: Use tools like Foundry or Hardhat for deploying contracts. This project uses
  [PaulRBerg's foundry-template](https://github.com/PaulRBerg/foundry-template), which is a template optimized for
  developing Solidity smart contracts with Foundry, incorporating sensible defaults.
- **MockUSDC and MockNFT Contracts**: Ensure that MockUSDC and MockNFT contracts are deployed for comprehensive testing
  of the platform.

These tools and accounts will equip you with the necessary environment to launch and test the NFTLendHub effectively.

#### Installation

1. Clone the repository:
   ```
   git clone <repository-url>
   ```
2. Install dependencies:
   ```
   bun install
   ```
3. Compile the contract:
   ```
   forge build
   ```
4. Run tests
   ```
   forge test
   ```

#### Deploy

This script deploys and verifies the NFTLendHub contract along with the auxiliary ERC20 and ERC721 contracts used for
testing purposes.

```
forge script script/DeployNFTLendHub.s.sol --rpc-url sepolia --broadcast --verify -vvvv
```

#### Interact with deployed contracts using TypeScript

This script interacts with the NFTLendHub, MockNFT, and MockUSDC contracts on the Sepolia network. It performs a series
of blockchain transactions including approving and transferring USDC, minting NFTs, and initiating a loan using an NFT
as collateral.

> After each deployment, the contract addresses must be updated in this script to ensure correct interaction with them.

```
npx ts-node tsscript/interactLendHub.ts
```

To interact with the deployed contracts, you can extract the ABI from the build artifacts using a command-line tool such
as `jq`.

```
cat out/NFTLendHub.sol/NFTLendHub.json | jq .abi > abi/contracts/NFTLendHub.sol/NFTLendHub.json
```

### Integrating Diligence Fuzzing

**Diligence Fuzzing** is an advanced fuzz testing tool developed by ConsenSys that aims to identify potential
vulnerabilities in Ethereum smart contracts. By generating random inputs and testing them against the contract's logic,
it helps uncover hidden issues that might not be easily caught through normal testing.

#### Why Use Diligence Fuzzing?

Fuzzing is essential for ensuring the robustness of smart contracts by exposing them to a wide range of input
conditions. Diligence Fuzzing offers:

- Automated discovery of vulnerabilities.
- Easy integration with Solidity and Foundry.
- Comprehensive documentation and support.

#### Getting Started with Diligence Fuzzing on Existing Foundry Projects

To integrate Diligence Fuzzing into your existing Foundry project and start fuzz testing your contracts, follow these
detailed steps based on the
[official tutorial](https://fuzzing-docs.diligence.tools/getting-started/fuzzing-foundry-projects).

1. **Install the CLI and Configure the API Key**
   - Ensure Foundry is installed and make sure you’re at least python 3.6 and node 16. You can add Diligence Fuzzing to
     your project by running:
     ```bash
     pip3 install diligence-fuzzing
     ```
2. **API Key**

   - With the tools installed, you will need to generate an API for the CLI and add it to the `.env` file. The API keys
     menu is [accessible here](https://fuzzing.diligence.tools/keys).

3. **Running Fuzz Tests**

   - Run your fuzz tests to see how your contract behaves under random conditions:
     ```bash
     fuzz forge test
     ```
   - This sequence compiles unit tests, automatically detects and collects test contracts, and submits them for fuzzing:

     ```bash
     $ fuzz forge test

     🛠️  Parsing Foundry configuration
     🛠️  Compiling tests
     🛠️  Gathering test contracts
     🛠️  Assembling and validating campaigns for submission
     🛠️  Configuring the initial seed state
     ⚡️ Launching fuzzing campaigns
     You can track the progress of the campaign here: [Campaign Dashboard](https://fuzzing.diligence.tools/campaigns/cmp_ffcd3abf6b0640598c7cc7e436717xxx)
     Done 🎉
     ```

   - Visit the provided URL to access the Campaign Dashboard where you can monitor detailed statistics and results of
     the fuzzing process.

#### Recommendations

- **Consult the Official Documentation**: For comprehensive guidance and advanced techniques, visit the
  [Diligence Fuzzing Documentation](https://fuzzing-docs.diligence.tools/getting-started/fuzzing-foundry-projects).
- **Incorporate Regular Fuzz Testing**: Include fuzz testing in your regular testing routines to continuously improve
  the security and reliability of your contracts.
