// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./TokenContract.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CustomERC1155Factory is Ownable {
    event TokenContractCreated(address indexed creator, address indexed tokenContract);

    address[] public createdContracts;
    mapping(address => address[]) public creatorToContracts;

    function createTokenContract(string memory _uri) public returns (address) {
        TokenContract newContract = new TokenContract(_uri);
        newContract.transferOwnership(msg.sender);
        createdContracts.push(address(newContract));
        creatorToContracts[msg.sender].push(address(newContract));
        emit TokenContractCreated(msg.sender, address(newContract));
        return address(newContract);
    }

    function createTokenContractAndMint(
        string memory _uri,
        address _account,
        uint256 _id,
        uint256 _amount,
        string memory _tokenURI,
        bytes memory _data
        ) public returns (address) {
        TokenContract newContract = new TokenContract(_uri);
        newContract.transferOwnership(msg.sender);
    // Mint tokens
        newContract.mint(_account, _id, _amount, _tokenURI, _data);
    // Add contract to tracking arrays and mappings
        createdContracts.push(address(newContract));
        creatorToContracts[msg.sender].push(address(newContract));
    // Emit event
        emit TokenContractCreated(msg.sender, address(newContract));
        return address(newContract);
    }

    function getContractCount() public view returns (uint256) {
        return createdContracts.length;
    }

    function getContractAddress(uint256 _index) public view returns (address) {
        require(_index < createdContracts.length, "Index out of bounds");
        return createdContracts[_index];
    }

    function getCreatorContractCount(address _creator) public view returns (uint256) {
        return creatorToContracts[_creator].length;
    }

    function getAllContractsByCreator(address _creator) public view returns (uint256[]) {
        return creatorToContracts[_creator];
    }

    function getCreatorContractAddress(address _creator, uint256 _index) public view returns (address) {
        require(_index < creatorToContracts[_creator].length, "Index out of bounds");
        return creatorToContracts[_creator][_index];
    }
}