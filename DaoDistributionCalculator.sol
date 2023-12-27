// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { AxelarExecutable } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/executable/AxelarExecutable.sol';
import { IAxelarGateway } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol';
import 'hardhat/console.sol';

contract DaoDistributionCalculator is AxelarExecutable {

    string public layerOneChain;
    string public layerOneContractAddress;
    address public immutable owner;

    event SentDistributions(string destinationChain, string contractAddress, bytes payload);

    constructor(address gateway_) AxelarExecutable(gateway_) {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, 'Not authorized');
        _;
    }

    modifier validConfig() {
        require(bytes(layerOneChain).length > 0, 'L1 chain not configured');
        require(bytes(layerOneContractAddress).length > 0, 'L1 chain not configured');
        _;
    }

    function configureLayerOne(
        string memory layerOneChain_,
        string memory layerOneContractAddress_
    ) external onlyOwner {
        layerOneChain = layerOneChain_;
        layerOneContractAddress = layerOneContractAddress_;
    }    

    function _execute(
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) internal override validConfig {
        console.log(" -- dist: initiate _execute ");


        (address[] memory addresses, uint256 tokenSupply) = abi.decode(payload, (address[], uint256));

        // Do the distribution calculation
        uint256[] memory amounts = calculateDistribution(addresses, tokenSupply, msg.sender);

        // send the results back to the layer one
        bytes memory destPayload = abi.encode(addresses, amounts);
        gateway.callContract(sourceChain, sourceAddress, destPayload);

        emit SentDistributions(sourceChain, sourceAddress, destPayload);
    }

    function calculateDistribution(
        address[] memory addresses,
        uint256 tokenSupply,
        address sender
    ) internal view returns (uint256[] memory) {
        uint256[] memory amounts = new uint256[](addresses.length);
        for (uint i = 0; i < addresses.length; i++) {
            amounts[i] = uint(keccak256(abi.encodePacked(block.timestamp, sender, addresses[i]))) % tokenSupply + 1;
        }
        return amounts;
    }

}
