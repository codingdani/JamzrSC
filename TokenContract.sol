// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract TokenContract is ERC1155, Ownable, Initializable {
    using Strings for uint256;

    // maps token ID to metadata URI
    mapping(uint256 => string) private tokenURIs;

    // maps token ID to royalty information
    mapping(uint256 => RoyaltyInfo) private royalties;

    struct RoyaltyInfo {
        address recipient;
        uint256 percentage;
    }

    constructor(string memory _uri) ERC1155(_uri) {}

    function mint(
        address _receiver, 
        uint256 _id, 
        uint256 _amount, 
        string memory _newuri, 
        bytes memory _data
        ) public onlyOwner {
        _mint(_receiver, _id, _amount, _data);
        setTokenURI(_id, _newuri);
    }

    function mintBatch(
        address _receiver, 
        uint256[] memory _ids, 
        uint256[] memory _amounts, 
        bytes memory _data
        ) public onlyOwner {
        _mintBatch(_receiver, _ids, _amounts, _data);
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
}