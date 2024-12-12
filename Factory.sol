// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./TokenContract.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CustomERC1155Factory is Ownable {
    event TokenContractCreated(address indexed creator, address indexed tokenContract, string name);

    address[] public createdContracts;
    mapping(address => address[]) public creatorToContracts;

    constructor(address initialOwner) Ownable(initialOwner) {}

    function createTokenContract(string calldata _baseURI, string calldata _name) public 
    returns (address) {
        TokenContract newContract = new TokenContract(_name, _baseURI, msg.sender);
        createdContracts.push(address(newContract));
        creatorToContracts[msg.sender].push(address(newContract));
        emit TokenContractCreated(msg.sender, address(newContract), _name);
        return address(newContract);
    }

    function createTokenContractAndMint(
        string calldata _name,
        string calldata _baseURI,
        address _receiver,
        uint256 _amount,
        string calldata _tokenURI,
        address _royaltyRecipient,
        uint256 _royaltyPercentage,
        bytes calldata _data
    ) public returns (address, uint256) {
        TokenContract newContract = new TokenContract(_name, _baseURI, address(this));
        // Mint tokens
        uint256 tokenId = newContract.mint(
            _receiver, 
            _amount, 
            _tokenURI, 
            _royaltyRecipient, 
            _royaltyPercentage, 
            _data);
        // Add contract to tracking arrays and mappings
        createdContracts.push(address(newContract));
        // Transfer ownership to the caller (msg.sender)
        newContract.transferOwnership(msg.sender);
        creatorToContracts[msg.sender].push(address(newContract));
        // Emit event
        emit TokenContractCreated(msg.sender, address(newContract), _name);
        return (address(newContract), tokenId);
    }

    function getAllContractsByCreator(address _creator) public view 
    returns (address[] memory) {
        return creatorToContracts[_creator];
    }
}