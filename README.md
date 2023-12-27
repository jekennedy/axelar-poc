# Protocol X DAO Distribution

To support their upcoming DAO token distribution event, ProtocolX utilizes a complicated algorithm to determine fair token distribution. Although their DApp resides on Ethereum mainnet, the execution of the token distribution algorithm should be performed on an L2. 

To support this requirement, this project leverages Axelar’s GMP capabilities to perform the execution on a specified L2. DAO members can then claim their tokens on Ethereum.

## Prerequisite

Set up your local development environment: https://github.com/axelarnetwork/axelar-local-dev

## Deployment

```bash
npm run build
npm run start
npm run deploy evm/protocolx local
```

## Execution

```bash
npm run execute evm/send-ack [local|testnet] ${srcChain} ${destChain} ${srcChainContractAddress} ${destChainContractAddress}
```

## Example

```bash
npm run execute evm/protocolx local "Ethereum" "Polygon" "0x12dC9f4Fb864dE64750E0A87a1a8110509B4f7BB" "0xA6B6773a942571169cB7EA2ABeBEbBf0c077f353"
```

**Output:**

```
L1 contract is configured to Polygon, L2 contract is configured to Ethereum
******  token distributions: address1 = 54193500, address2 = 4556890 ******
****** Balances of wallets before claim: 0, 0 ******
Claimed 54193500 tokens for 1st address
Expected Error: 1st address has already claimed tokens
Claimed 4556890 tokens for 2nd address
Expected Error: 2nd address has already claimed tokens
****** Balances of wallets after claim: 54193500, 4556890 ******
```
Note: The values in the first line (token distributions) and the last line (wallet balances after distribution) should be the same.