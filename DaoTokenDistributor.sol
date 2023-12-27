// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IAxelarGateway } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol';
import { IAxelarGasService } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGasService.sol';
import { ERC20 } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/test/token/ERC20.sol';
import { AxelarExecutable } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/executable/AxelarExecutable.sol';
import { Upgradable } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/upgradable/Upgradable.sol';
import { StringToAddress, AddressToString } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/libs/AddressString.sol';

contract DaoTokenDistributor is AxelarExecutable, ERC20, Upgradable {
    using StringToAddress for string;
    using AddressToString for address;

    error NotEnoughValueForGas();
    error AlreadyInitialized();

    event RequestedDistributions(string destinationChain, string contractAddress, bytes payload);
    event ReceivedDistributions(string sourceChain, string contractAddress, bytes payload);

    mapping(address => uint256) public distributions;
    IAxelarGasService public immutable gasService;
    string public layerTwoChain;
    string public layerTwoContractAddress;
    address public immutable installer;

    constructor(
        address gateway_,
        address gasReceiver_,
        uint8 decimals_
    ) AxelarExecutable(gateway_) ERC20('', '', decimals_) {
        gasService = IAxelarGasService(gasReceiver_);
        installer = msg.sender;
    }

    modifier onlyInstaller() {
        require(msg.sender == installer, 'Not authorized');
        _;
    }

    modifier validConfig() {
        require(bytes(layerTwoChain).length > 0, 'L2 chain not configured');
        require(bytes(layerTwoContractAddress).length > 0, 'L2 chain not configured');
        _;
    }

    function configureLayerTwo(
        string memory layerTwoChain_,
        string memory layerTwoContractAddress_
    ) external onlyInstaller {
        layerTwoChain = layerTwoChain_;
        layerTwoContractAddress = layerTwoContractAddress_;
    }

    // sends the request to the layerTwo contract to perform the token distribution calculation
    function calculateTokenDistribution(
        bytes calldata payload
    ) external payable onlyInstaller {
        if (msg.value == 0)  revert NotEnoughValueForGas();
        emit RequestedDistributions(layerTwoChain, layerTwoContractAddress, payload);

        gasService.payNativeGasForContractCall{ value: msg.value }(
            address(this),
            layerTwoChain,
            layerTwoContractAddress,
            payload,
            msg.sender
        );

        gateway.callContract(layerTwoChain, layerTwoContractAddress, payload);
    }

    // receives the token distributions calculation from the layerTwo and stores the results locally
    function _execute(
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) internal override {
        emit ReceivedDistributions(sourceChain, sourceAddress, payload);

        require(keccak256(abi.encodePacked(sourceChain)) == keccak256(abi.encodePacked(layerTwoChain)), 'L2 chains mismatch');
        require(keccak256(abi.encodePacked(sourceAddress)) == keccak256(abi.encodePacked(layerTwoContractAddress)), 'L2 addresses mismatch');

        (address[] memory addresses_, uint256[] memory amounts_) = abi.decode(payload, (address[], uint256[]));
        require(addresses_.length == amounts_.length, 'addresses/amounts lengths differ');

        for (uint i = 0; i < addresses_.length; i++) {
            distributions[addresses_[i]] = amounts_[i];
        }
    }

    function claimTokens() external payable {
        require(distributions[msg.sender] != 0, 'address does not qualify');

        uint256 amount = distributions[msg.sender];
        _mint(msg.sender, amount);
        distributions[msg.sender] = 0;
    }

    function claimTokensTest(address recipient) external payable {
        require(distributions[recipient] != 0, 'address does not qualify');

        uint256 amount = distributions[recipient];
        _mint(recipient, amount);
        distributions[recipient] = 0;
    }    

    function _setup(bytes calldata params) internal override {
        (string memory name_, string memory symbol_) = abi.decode(params, (string, string));
        if (bytes(name).length != 0) revert AlreadyInitialized();
        name = name_;
        symbol = symbol_;
    }

    function contractId() external pure returns (bytes32) {
        return keccak256('example');
    }
}
