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
        uint256 _id, 
        uint256 _amount, 
        string memory _newuri, 
        bytes memory _data
        ) public onlyOwner {
        if (tokenDetails[_id].totalSupply == 0) {
                allTokenIds.push(_id);
            }
        tokenDetails[_id].totalSupply += _amount;
        tokenDetails[_id].uri = _newuri;
        _mint(_receiver, _id, _amount, _data);
        setTokenURI(_id, _newuri);
    }

    function mintBatch(
        address _receiver,
        uint256[] memory _ids,
        uint256[] memory _amounts,
        string[] memory _uris,
        bytes memory _data
    ) public onlyOwner {
        require(_ids.length == _amounts.length && _ids.length == _uris.length, "Arrays length mismatch");
        for (uint256 i = 0; i < _ids.length; i++) {
            uint256 id = _ids[i];
            uint256 amount = _amounts[i];
            string memory uri = _uris[i];
            if (_tokenDetails[id].totalSupply == 0) {
                _allTokenIds.push(id);
            }
            _tokenDetails[id].totalSupply += amount;
              _tokenDetails[id].uri = uri;
            setTokenURI(id, uri);
        }
        _mintBatch(_receiver, _ids, _amounts, _data);
    }

    function getAllTokenIds() public view returns (uint256[] memory) {
    return allTokenIds; 
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