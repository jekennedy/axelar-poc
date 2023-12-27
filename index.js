'use strict';

const {
    getDefaultProvider,
    constants: { AddressZero },
    utils: { defaultAbiCoder },
    BigNumber,
    Wallet,
} = require('ethers');

const {
    utils: { deployContract },
} = require('@axelar-network/axelar-local-dev');

const { deployUpgradable } = require('@axelar-network/axelar-gmp-sdk-solidity');

const DaoTokenDistributor = rootRequire('./artifacts/examples/evm/protocolx/DaoTokenDistributor.sol/DaoTokenDistributor.json');
const DaoDistributionCalculator = rootRequire(
    './artifacts/examples/evm/protocolx/DaoDistributionCalculator.sol/DaoDistributionCalculator.json',
);
const ExampleProxy = rootRequire('./artifacts/examples/evm/Proxy.sol/ExampleProxy.json');

// DAO token config
const name = 'ProtocolX Dao Token';
const symbol = 'PROX';
const decimals = 13;

async function deploy(chain, wallet) {
    chain.provider = getDefaultProvider(chain.rpc);
    chain.wallet = wallet.connect(chain.provider);

    console.log(`Deploying DaoTokenDistributor for ${chain.name}.`);
    chain.distributor = await deployUpgradable(
        chain.constAddressDeployer,
        wallet,
        DaoTokenDistributor,
        ExampleProxy,
        [chain.gateway, chain.gasService, decimals],
        [],
        defaultAbiCoder.encode(['string', 'string'], [name, symbol]),
        'protocolx',
    );
    console.log(`Deployed DaoTokenDistributor for ${chain.name} at ${chain.distributor.address}.`);

    console.log(`Deploying DaoDistributionCalculator for ${chain.name}.`);
    chain.calculator = await deployContract(wallet, DaoDistributionCalculator, [chain.gateway]);
    console.log(`Deployed DaoDistributionCalculator for ${chain.name} at ${chain.calculator.address}.`);
}

async function execute(chains, wallet, options) {
    const { source, destination, calculateBridgeFee, args } = options;
    const l1Chain = args[0];
    const l2Chain = args[1];
    const l1Contract = args[2];
    const l2Contract = args[3];

    const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

    // configure distributor contract to use the L2 calculator contract
    const l2Chain_ = await source.distributor
        .configureLayerTwo(l2Chain, l2Contract)
        .then(txConfigL1 => txConfigL1.wait())
        .then(async () => await source.distributor.layerTwoChain());        

    // configure calculator contract to use the L1 distributor contract
    const l1Chain_ = await destination.calculator
        .configureLayerOne(l1Chain, l1Contract)
        .then(txConfigL2 => txConfigL2.wait())
        .then(async () => await destination.calculator.layerOneChain());

    console.log(`L1 contract is configured to ${l2Chain_}, L2 contract is configured to ${l1Chain_}`);

    // create some wallet addresses for the payload 
    const wallets = generateWallets(5, source.provider);
    let addresses = [wallets[wallets.length - 1].address, wallets[0].address];

    const tokenSupply = 123456790;
    const payload = defaultAbiCoder.encode(['address[]', 'uint256'], [addresses, tokenSupply]);

    // calculate two-way call bridge fees
    const feeSource = await calculateBridgeFee(source, destination);
    const feeRemote = await calculateBridgeFee(destination, source);
    const totalFee = BigNumber.from(feeSource).add(feeRemote);

    // initiate the token distribution calculation
    const txCalc = await source.distributor
        .calculateTokenDistribution(payload, {
            value: totalFee,
        })
        .then((txCalc) => txCalc.wait());

    // Wait for txn to complete on the way back
    //TODO find a better way to do this
    await sleep(4000);

    // check the distribution amount for the first address and last address
    var amount1 = await source.distributor.distributions(addresses[0]);
    var amount2 = await source.distributor.distributions(addresses[addresses.length - 1]);
    console.log(`******  token distributions: address1 = ${amount1}, address2 = ${amount2} ******`);

    // verify the payload in the emitted event matches what was initially sent
    const eventDist = txCalc.events.find((eventDist) => eventDist.event === 'RequestedDistributions');
    const eventDistPayload = defaultAbiCoder.decode(['address[]', 'uint256'], eventDist.args.payload);
    //console.log(`${typeof(tokenSupply)} , ${typeof(eventDistPayload[1])}`);
    if(tokenSupply !== Number(eventDistPayload[1])) throw error("tokenSupply mistmatch");
    //TODO any way we can get the events from the L2 calculator contract? 

    // check balances before claims
    let balance1 = await source.distributor.balanceOf(addresses[0]);
    let balance2 = await source.distributor.balanceOf(addresses[addresses.length - 1]);
    console.log(`****** Balances of wallets before claim: ${balance1.toString()}, ${balance2.toString()} ******`);

    // claim the tokens for the first address - should succeed
    try {
        balance1 = await source.distributor
            .claimTokensTest(addresses[0])
            .then((txClaim) => txClaim.wait()
            .then(async () => await source.distributor.balanceOf(addresses[0])));
            console.log(`Claimed ${balance1.toString()} tokens for 1st address`);
        } catch (error) {
        console.log('Error: 1st address: Claim tokens failed (${error.message}');
    }

    // retry - should fail because they've already been claimed
    try {
        balance1 = await source.distributor
            .claimTokensTest(addresses[0])
            .then((txClaim) => txClaim.wait()
            .then(async () => await source.distributor.balanceOf(addresses[0])));
        console.log(`1st address: Shouldn't reach here!! ${balance1.toString()}`);
    } catch (error) {
        console.log(`Expected Error: 1st address has already claimed tokens`);
    }    

    // claim the tokens for the second address - should succeed
    try {
        balance2 = await source.distributor
            .claimTokensTest(addresses[1])
            .then((txClaim) => txClaim.wait()
            .then(async () => await source.distributor.balanceOf(addresses[1])));
            console.log(`Claimed ${balance2.toString()} tokens for 2nd address`);
    } catch (error) {
        console.log('Error: 2nd address: Claim tokens failed (${error.message}');
    }

    // retry - should fail because they've already been claimed
    try {
        balance2 = await source.distributor
            .claimTokensDelegate(addresses[1])
            .then((txClaim2) => txClaim2.wait()
            .then(async () => await source.distributor.balanceOf(addresses[1])));
            console.log(`Shouldn't reach here!! ${balance2.toString()}`);
    } catch (error) {
        console.log(`Expected Error: 2nd address has already claimed tokens`);
    }
    console.log(`****** Balances of wallets after claim: ${balance1.toString()}, ${balance2.toString()} ******`);
}

function generateWallets(amount, provider) {
    let wallets = new Array(amount);
    for(var i = 0; i < amount; i++) {
        wallets[i] = Wallet.createRandom().connect(provider);
    }
    return wallets;
}

module.exports = {
    deploy,
    execute,
};
