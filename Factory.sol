// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./CustomERC1155WithRoyalties.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CustomERC1155Factory is Ownable {
    event TokenContractCreated(address indexed creator, address indexed tokenContract);

    address[] public createdContracts;
    mapping(address => address[]) public creatorToContracts;

    function createTokenContract(string memory uri) public returns (address) {
        CustomERC1155WithRoyalties newContract = new CustomERC1155WithRoyalties(uri);
        newContract.transferOwnership(msg.sender);
        createdContracts.push(address(newContract));
        creatorToContracts[msg.sender].push(address(newContract));
        emit TokenContractCreated(msg.sender, address(newContract));
        return address(newContract);
    }

    function getContractCount() public view returns (uint256) {
        return createdContracts.length;
    }

    function getContractAddress(uint256 index) public view returns (address) {
        require(index < createdContracts.length, "Index out of bounds");
        return createdContracts[index];
    }

    function getCreatorContractCount(address creator) public view returns (uint256) {
        return creatorToContracts[creator].length;
    }

    function getAllContractsByCreator(address creator) public view returns (uint256[]) {
        return creatorToContracts[creator];
    }

    function getCreatorContractAddress(address creator, uint256 index) public view returns (address) {
        require(index < creatorToContracts[creator].length, "Index out of bounds");
        return creatorToContracts[creator][index];
    }
}