// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract TokenContract is ERC1155, Ownable {
    using Strings for uint256;

    event TokenMinted(uint256 indexed tokenId, address indexed receiver, uint256 amount, string tokenURI);

    string public name;
    uint256 private nextTokenId;

    struct TokenDetails {
    uint256 totalSupply;
    string uri;
    address royaltyRecipient;
    uint256 royaltyPercentage;
    }
    //maps token ID to TokenDetails
    mapping(uint256 => TokenDetails) private tokenDetails;

    constructor(string calldata _name, string calldata _baseURI, address _owner) 
    ERC1155(_baseURI) 
    Ownable(_owner) {
        name = _name;
    }

    function mint(
        address _receiver,
        uint256 _amount,
        string calldata _tokenURI,
        address _royaltyRecipient,
        uint256 _royaltyPercentage,
        bytes calldata _data
    ) external onlyOwner returns (uint256) {
        require(_amount > 0, "Amount must be greater than 0");
        require(_royaltyPercentage <= 10000, "Royalty percentage cannot exceed 100%");
        uint256 tokenId = nextTokenId++;
        tokenDetails[tokenId] = TokenDetails({
            totalSupply: _amount,
            uri: _tokenURI,
            royaltyRecipient: _royaltyRecipient,
            royaltyPercentage: _royaltyPercentage
        });
        _mint(_receiver, tokenId, _amount, _data);
        emit TokenMinted(tokenId, _receiver, _amount, _tokenURI);
        return tokenId;
    }

    function mintBatch(
        address _receiver,
        uint256[] calldata _amounts,
        string[] calldata _uris,
        address[] calldata _royaltyRecipients,
        uint256[] calldata _royaltyPercentages,
        bytes calldata _data
    ) external onlyOwner {
        require(_amounts.length == _uris.length && 
                _amounts.length == _royaltyRecipients.length && 
                _amounts.length == _royaltyPercentages.length, 
                "Arrays length mismatch");
        uint256[] memory newIds = new uint256[](_amounts.length);
        for (uint256 i = 0; i < _amounts.length; i++) {
            require(_amounts[i] > 0, "Amount must be greater than 0");
            require(_royaltyPercentages[i] <= 10000, 
            "Royalty percentage cannot exceed 100%");
            uint256 newId = nextTokenId++;
            newIds[i] = newId;
            tokenDetails[newId] = TokenDetails({
                totalSupply: _amounts[i],
                uri: _uris[i],
                royaltyRecipient: _royaltyRecipients[i],
                royaltyPercentage: _royaltyPercentages[i]
            });
            emit TokenMinted(newId, _receiver, _amounts[i], _uris[i]);
        }
        _mintBatch(_receiver, newIds, _amounts, _data);
    }

    function getTokenDetails(uint256 _tokenId) external view returns (
        uint256 totalSupply, 
        string memory tokenUri,
        address royaltyRecipient,
        uint256 royaltyPercentage
        ) {
        TokenDetails memory details = tokenDetails[_tokenId];
        return (
            details.totalSupply, 
            details.uri, 
            details.royaltyRecipient, 
            details.royaltyPercentage
            );
    }

    // function getAllTokensWithDetails() external view returns (
    // uint256[] memory _ids,
    // uint256[] memory _supplies,
    // string[] memory _uris
    // ) {
    //     uint256 length = _allTokenIds.length;
    //     ids = new uint256[](length);
    //     supplies = new uint256[](length);
    //     uris = new string[](length);

    //     for (uint256 i = 0; i < length; i++) {
    //         uint256 id = _allTokenIds[i];
    //         ids[i] = id;
    //         supplies[i] = _tokenDetails[id].totalSupply;
    //         uris[i] = _tokenDetails[id].uri;
    //     }

    //     return (ids, supplies, uris);
    // }

    function setTokenRoyalty(
        uint256 _tokenId, 
        address _recipient, 
        uint256 _percentage
    ) external onlyOwner {
        require(_percentage <= 10000, "Royalty percentage cannot exceed 100%");
        TokenDetails storage details = tokenDetails[_tokenId];
        details.royaltyRecipient = _recipient;
        details.royaltyPercentage = _percentage;
    }

    function setTokenURI(uint256 _tokenId, string calldata _newURI) external onlyOwner {
        tokenDetails[_tokenId].uri = _newURI;
    }
    
    function setName(string calldata _newName) external onlyOwner {
        name = _newName;
    }
}