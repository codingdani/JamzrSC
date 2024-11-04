// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./TokenContract.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CustomERC1155Factory is Ownable {
    event TokenContractCreated(address indexed creator, address indexed tokenContract, string name);

    address[] public createdContracts;
    mapping(address => address[]) public creatorToContracts;

    constructor(address initialOwner) Ownable(initialOwner) {}

    function createTokenContract(string memory _baseURI, string memory _name) public 
    returns (address) {
        TokenContract newContract = new TokenContract(_name, _baseURI, msg.sender);
        createdContracts.push(address(newContract));
        creatorToContracts[msg.sender].push(address(newContract));
        emit TokenContractCreated(msg.sender, address(newContract), _name);
        return address(newContract);
    }

    function createTokenContractAndMint(
        string memory _name,
        string memory _baseURI,
        address _receiver,
        uint256 _amount,
        string memory _tokenURI,
        address _royaltyRecipient,
        uint256 _royaltyPercentage,
        bytes memory _data
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

    function getContractCount() public view returns (uint256) {
        return createdContracts.length;
    }

    function getContractAddress(uint256 _index) public view 
    returns (address) {
        require(_index < createdContracts.length, "Index out of bounds");
        return createdContracts[_index];
    }

    function getCreatorContractCount(address _creator) public view 
    returns (uint256) {
        return creatorToContracts[_creator].length;
    }

    function getAllContractsByCreator(address _creator) public view 
    returns (address[] memory) {
        return creatorToContracts[_creator];
    }

    function getCreatorContractAddress(address _creator, uint256 _index) public view 
    returns (address) {
        require(_index < creatorToContracts[_creator].length, "Index out of bounds");
        return creatorToContracts[_creator][_index];
    }
}