// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract TokenContract is ERC1155, Ownable, Initializable {
    using Strings for uint256;

    string public name;

    uint256[] private allTokenIds;
    uint256 private nextTokenId;

    struct TokenDetails {
    uint256 totalSupply;
    string uri;
    }
    mapping(uint256 => TokenDetails) private tokenDetails;

    // maps token ID to metadata URI
    mapping(uint256 => string) private tokenURIs;

    // maps token ID to royalty information
    mapping(uint256 => RoyaltyInfo) private royalties;

    struct RoyaltyInfo {
        address recipient;
        uint256 percentage;
    }

    constructor(string memory _baseUri, string memory _name) ERC1155(_baseUri) {
        name = _name;
    }

    function mint(
        address _receiver,
        uint256 _amount,
        string memory _newuri,
        bytes memory _data
    ) public onlyOwner {
        uint256 tokenId = nextTokenId++;
        tokenDetails[tokenId] = TokenDetails({
            totalSupply: _amount,
            uri: _newuri
        });
        allTokenIds.push(tokenId);
        _mint(_receiver, tokenId, _amount, _data);
        setTokenURI(tokenId, _newuri);
        emit TokenMinted(tokenId, _receiver, _amount, _newuri);
}

    function mintBatch(
        address _receiver,
        uint256[] memory _amounts,
        string[] memory _uris,
        bytes memory _data
    ) public onlyOwner {
        require(_amounts.length == _uris.length, "Arrays length mismatch");
        uint256[] memory newIds = new uint256[](_amounts.length);
        for (uint256 i = 0; i < _amounts.length; i++) {
            uint256 newId = nextTokenId++;
            newIds[i] = newId;
            tokenDetails[newId] = TokenDetails({
                totalSupply: _amounts[i],
                uri: _uris[i]
            });
            allTokenIds.push(newId);
            setTokenURI(newId, _uris[i]);
            emit TokenMinted(newId, _receiver, _amounts[i], _uris[i]);
        }
        _mintBatch(_receiver, newIds, _amounts, _data);
    }   

    function getAllTokenIds() public view returns (uint256[] memory) {
    return allTokenIds; 
    }

    function getTotalUniqueTokens() public view returns (uint256) {
    return nextTokenId > 0 ? nextTokenId - 1 : 0;
}   

    function getTokenDetails(uint256 _tokenId) public view returns (
        uint256 totalSupply, 
        string memory tokenUri
        ) {
    TokenDetails memory details = tokenDetails[_tokenId];
    return (details.totalSupply, details.uri);
    }

    function getAllTokensWithDetails() public view returns (
    uint256[] memory _ids,
    uint256[] memory _supplies,
    string[] memory _uris
    ) {
        uint256 length = _allTokenIds.length;
        ids = new uint256[](length);
        supplies = new uint256[](length);
        uris = new string[](length);

        for (uint256 i = 0; i < length; i++) {
            uint256 id = _allTokenIds[i];
            ids[i] = id;
            supplies[i] = _tokenDetails[id].totalSupply;
            uris[i] = _tokenDetails[id].uri;
        }

        return (ids, supplies, uris);
    }

    function setTokenRoyalty(
        uint256 _tokenId, 
        address _recipient, 
        uint256 _percentage
        ) public onlyOwner {
        require(_percentage <= 10000, "Royalty percentage cannot exceed 100%");
        royalties[tokenId] = RoyaltyInfo(_recipient, _percentage);
    }

    function royaltyInfo(
        uint256 _tokenId, 
        uint256 _salePrice
        ) public view returns (
            address receiver, 
            uint256 royaltyAmount
            ) {
        RoyaltyInfo memory royalty = royalties[_tokenId];
        return (royalty.recipient, (_salePrice * royalty.percentage) / 10000);
    }

    function setTokenURI(uint256 _tokenId, string memory _newuri) private {
        tokenURIs[_tokenId] = _newuri;
    }

    function uri(uint256 _tokenId) public view virtual override 
    returns (string memory) {
        string memory tokenURI = tokenURIs[_tokenId];
        if (bytes(tokenURI).length > 0) {
            return tokenURI;
        }
        return super.uri(_tokenId);
    }

    function setName(string memory _newName) public onlyOwner {
        name = _newName;
    }
}