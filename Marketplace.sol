// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract NFTMarketplace is ReentrancyGuard, Ownable {
    using EnumerableSet for EnumerableSet.UintSet;
//ZU BEACHTEN: 
// Alle Käufer sollen gleiche Gas Fees zahlen (der letzte Käufer soll nicht alle state changes zahlen müssen)
// Der Marketplace ist jetzt nur Operator. Die Token werden im Wallet der Besitzer gelassen 
// Cleanup von inActive Listings sollte vom Ersteller übernommen werden 

    struct Listing {
        uint256 listingId;
        address tokenContract;
        address seller;
        uint256 tokenId;
        uint256 price;
        uint256 quantity;
        bool isActive;
        uint256 timestamp;
    }
    //maps listindId to Listing
    mapping(uint256 => Listing) public listings;
    uint256 private listingCounter;

    EnumerableSet.UintSet public activeListings;
    //maps sellerAddress to Set of listingId
    mapping(address => EnumerableSet.UintSet) public sellerListings;
    //maps tokenContractAddress to TokenId to Set of listingId
    mapping(address => mapping(uint256 => EnumerableSet.UintSet)) public assignTokenToListings;
    //maps listingId to bool to indicate that Listing needs to be removed from all mappings
    mapping(uint256 => bool) public listingNeedsCleanup;

    struct Transaction {
        uint256 listingId;
        address buyer;
        uint256 price;
        uint256 mfee;
        uint256 quantity;
        uint256 timestamp;
    }
    //maps listingId to Array of Transactions
    mapping(uint256 => Transaction[]) public listingTransactions;

    mapping(address => bool) public supportedTokenContracts;
    uint256 public marketplaceFeePercentage;

    event ListingCreated(
        uint256 indexed listingId, 
        address tokenContract,
        address indexed seller, 
        uint256 tokenId, 
        uint256 price, 
        uint256 quantity,
        uint createdAt
        );
    event ListingDeactivated(uint256 indexed listingId);
    event ListingDeleted(uint256 indexed listingId);
    event ListingUpdated(uint256 indexed listingId, uint256 remainingQuantity);
    event NFTPurchased(uint256 indexed listingId, address indexed buyer, uint256 quantity);
    event TokenSold(
        uint256 indexed listingId, 
        address indexed tokenContract, 
        address indexed seller, 
        address buyer, 
        uint256 tokenId, 
        uint256 quantity, 
        uint256 price
        );
    event MarketplaceFeeUpdated(uint256 newFeePercentage);

    constructor(uint256 _initialFeePercentage) {
        marketplaceFeePercentage = _initialFeePercentage;
        owner = msg.sender;
    }

//All Listing Operations: create, delete, removeFromMappings, deactivate, cleanup // Utils: getAllActiveListings, getListingsForToken, getSellerListings, getListingDetailsFromId

    function createListing(address _tokenContract, uint256 _tokenId, uint256 _price, uint256 _quantity) public returns (uint256) {
        require(supportedTokenContracts[_tokenContract], "Token contract not supported");    
        require(IERC1155(_tokenContract).balanceOf(msg.sender, _tokenId) >= _quantity, "Insufficient token balance");
    //marketplace has to be set as Operator in Token-Smart-Contract via setApprovalForAll()-Function 
        require(IERC1155(_tokenContract).isApprovedForAll(msg.sender, address(this)), "Contract not approved as operator");
        uint256 listingId = _getNextListingId();
        Listing memory newListing = Listing(
            listingId, 
            _tokenContract, 
            msg.sender, 
            _tokenId, 
            _price, 
            _quantity, 
            true, 
            block.timestamp
            );
        listings[listingId] = newListing;
        sellerListings[msg.sender].add(listingId);
        activeListings.add(listingId);
        assignTokenToListings[_tokenContract][_tokenId].add(_listingId);
        emit ListingCreated(
            newListing.listingId, 
            newListing.tokenContract, 
            newListing.seller, 
            newListing.tokenId, 
            newListing.price, 
            newListing.quantity, 
            newListing.timestamp
            );
        return listingId;
    }

    function deleteListing(uint256 _listingId) external {
        Listing storage listing = listings[_listingId];
        require(listing.seller == msg.sender, "Not the seller");
        activeListings.remove(_listingId);
        _removeFromSellerListings(listing.seller, _listingId);
        _removeFromAssignTokenToListings(listing.tokenContract, listing.tokenId, _listingId);
        delete listingNeedsCleanup[_listingId];
        delete listings[_listingId];
        emit ListingDeleted(_listingId);
    }

    function _removeFromSellerListings(address _seller, uint256 _listingId) internal {
        sellerListings[_seller].remove(_listingId);
    }

    function _removeFromAssignTokenToListings(address _tokenContract, uint256 _tokenId, uint256 _listingId) internal {
        assignTokenToListings[_tokenContract][_tokenId].remove(_listingId);
    }

    function _deactivateListing(Listing storage _listing, uint256 _listingId) internal {
    //should this function be included into buyNFT()-Function? Will increase gas fees for last buyer
        require(_listing.isActive, "Listing already deactivated");
        _listing.isActive = false;
        activeListings.remove(_listingId);
        listingNeedsCleanup[_listingId] = true;
        emit ListingDeactivated(_listingId);
    }

    function cleanupListing(uint256 _listingId) external {
    //only needs to exist when _deactivateListing is included into buyNFT Function
    //should be called by listing.seller or a reward could be included for all Users to collect after cleaning 
        require(listingNeedsCleanup[_listingId], "Listing doesn't need cleanup");
        Listing storage listing = listings[_listingId];
        _removeFromSellerListings(listing.seller, _listingId);
        _removeFromAssignTokenToListings(listing.tokenContract, listing.tokenId, _listingId);
        delete listingNeedsCleanup[_listingId];
        delete listings[_listingId];
        emit ListingDeleted(_listingId);
    }

//Listing Utils
    function _getNextListingId() private returns (uint256) {
        listingCounter++;
        return listingCounter;
    }

    function getAllActiveListings(uint256 _startIndex, uint256 _count) public view returns (Listing[] memory, bool) {
    //This Function can "lazy load" a specific number of Active Listings, which can be called from the Frontend
        uint256 totalActive = activeListings.length();
        uint256 endIndex = _startIndex + _count;
        if (endIndex > totalActive) {
            endIndex = totalActive;
        }
        uint256 resultCount = endIndex - _startIndex;
        Listing[] memory result = new Listing[](resultCount);
        for (uint256 i = 0; i < resultCount; i++) {
            uint256 listingId = activeListings.at(_startIndex + i);
            result[i] = listings[listingId];
        }
    //gibt das Array von Listings zurück und einen boolean, ob noch mehr Listings existieren
        return (result, endIndex < totalActive);
    }

    function getActiveListingsForContract(address _tokenContract, uint256 _startIndex, uint256 _count) 
        external view returns (Listing[] memory, bool) {
        Listing[] memory result = new Listing[](_count);
        uint256 resultIndex = 0;
        uint256 totalProcessed = 0;
        // Iterate through all tokenIds for the given contract
        mapping(uint256 => EnumerableSet.UintSet) storage contractListings = assignTokenToListings[_tokenContract];
        for (uint256 tokenId = 0; resultIndex < _count && totalProcessed < _startIndex + _count; tokenId++) {
            EnumerableSet.UintSet storage tokenListings = contractListings[tokenId];
            uint256 listingCount = tokenListings.length();
            for (uint256 i = 0; i < listingCount && resultIndex < _count; i++) {
                if (totalProcessed >= _startIndex) {
                    uint256 listingId = tokenListings.at(i);
                    Listing storage listing = listings[listingId];
                    if (listing.isActive) {
                        result[resultIndex] = listing;
                        resultIndex++;
                    }
                }
                totalProcessed++;
            }
        }
        // Resize the result array if we found fewer matching listings than requested
        assembly {
            mstore(result, resultIndex)
        }
        return (result, totalProcessed < _startIndex + _count);
    }

    function getListingsForToken(address _tokenContract, uint256 _tokenId) public view returns (uint256[] memory) {
        return assignTokenToListings[_tokenContract][_tokenId].values();
    }

    function getSellerListings(address _seller) public view returns (uint256[] memory) {
        return sellerListings[_seller].values();
    }

    function getListingDetailsFromId(uint256 _listingId) external view returns (Listing memory) {
        require(_listingId < listingCounter, "Listing does not exist");
        return listings[_listingId];
    }


//Purchase NFT Function
// no state updating (mappings and arrays) so the last buyer of the Token does not get punished with high gas fees when the Listing should be deactivated
    function buyNFT(uint256 _listingId, uint256 _quantity) external payable nonReentrant {
        Listing storage listing = listings[_listingId];
        require(listing.isActive, "Listing not active");
        require(_quantity <= listing.quantity, "Insufficient quantity available");
        uint256 totalPrice = listing.price * _quantity;
        require(msg.value >= totalPrice, "Insufficient payment");
        uint256 fee = (totalPrice * marketplaceFeePercentage) / 10000;
        uint256 sellerPayment = totalPrice - fee;
    //update quantity
        listing.quantity -= _quantity;
        if (listing.quantity == 0) {
            _deactivateListing(listing, _listingId);
            emit ListingDeactivated(_listingId);
        }
    // Perform transfers
        bool success = payable(listing.seller).send(sellerPayment);
        require(success, "Transfer to seller failed");
        success = payable(owner).send(fee);
        require(success, "Transfer of fee failed");
        IERC1155(listing.tokenContract)
        .safeTransferFrom(address(this), msg.sender, listing.tokenId, _quantity, "");
    // record transaction    
        listingTransactions[_listingId].push(Transaction(
            _listingId, 
            msg.sender, 
            listing.price,
            fee, 
            _quantity, 
            block.timestamp
        ));
        emit NFTPurchased(_listingId, msg.sender, _quantity);
        emit ListingUpdated(_listingId, listing.quantity);
    }


//Marketplace Functions
    function setMarketplaceFee(uint256 _newFeePercentage) external onlyOwner {
        require(_newFeePercentage <= 10000, "Fee percentage cannot exceed 100%");
    //fee shown is 100.00% a 5 percent fee would be 500//
        marketplaceFeePercentage = _newFeePercentage;
        emit MarketplaceFeeUpdated(_newFeePercentage);
    }

    function addSupportedTokenContract(address _tokenContract) external onlyOwner {
        supportedTokenContracts[_tokenContract] = true;
    }

    function removeSupportedTokenContract(address _tokenContract) external onlyOwner {
        supportedTokenContracts[_tokenContract] = false;
    }
}

