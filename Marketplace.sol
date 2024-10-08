// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract NFTMarketplace is ERC1155Holder, ReentrancyGuard, Ownable {
    using EnumerableSet for EnumerableSet.UintSet;
//ZU BEACHTEN: 
// Alle Käufer sollen gleiche Gas Fees zahlen (der letzte Käufer soll nicht alle state changes zahlen müssen)
// Der Marketplace ist jetzt nur Operator. Die Token werden im Wallet der Besitzer gelassen 
// Cleanup von inActive Listings sollte vom Ersteller übernommen werden => welche Funktionen braucht man wirklich? Sollten alle beibehalten werden?

//mögliche Probleme: Gleichzeitige Zustandsänderungen
// vielleicht auf eine Eventbasierte Architektur umsteigen, um Zustandsänderungen zu signalisieren
// vielleicht Versionsnummern Für Listings hinzufügen, um Konflikte bei gleichzeitigen Änderungen zu erkennen

    struct Listing {
        uint256 listingId;
        address tokenContract;
        address seller;
        uint256 tokenId;
        uint256 price;
        uint256 quantity;
        bool isActive;
    }
    //maps listindId to Listing
    mapping(uint256 => Listing) public listings;
    uint256 private listingCounter;

    //Für active Listing Verwaltung vielleicht Enumerable Set von Openzeppelin integrieren, kein Array
    EnumerableSet.UintSet private activeListings;
    //maps sellerAddress to Array of listingId
    mapping(address => uint256[]) public sellerListings;
    //maps tokenContractAddress to TokenId to Array of listingId
    mapping(address => mapping(uint256 => uint256[])) public assignTokenToListings;
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
        uint256 quantity
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


//All Listing Operations: create, getDetails, delete, removeFromMappings, deactivate, cleanupState

    function createListing(address _tokenContract, uint256 _tokenId, uint256 _price, uint256 _quantity) public {
        require(supportedTokenContracts[_tokenContract], "Token contract not supported");    
        require(IERC1155(_tokenContract).balanceOf(msg.sender, _tokenId) >= _quantity, "Insufficient token balance");
    //marketplace has to be set as Operator in Token-Smart-Contract via setApprovalForAll()-Function 
        require(IERC1155(_tokenContract).isApprovedForAll(msg.sender, address(this)), "Contract not approved as operator");
        uint256 listingId = _getNextListingId();
    //Creationg of Listing changed to memory for gas-efficiency
        Listing memory newListing = Listing(listingId, _tokenContract, msg.sender, _tokenId, _price, _quantity, true);
        listings[listingId] = newListing;
        sellerListings[msg.sender].push(listingId);
        activeListings.add(listingId);
        assignTokenToListings[_tokenContract][_tokenId].push(listingId);
        emit ListingCreated(listingId, _tokenContract, msg.sender, _tokenId, _price, _quantity);
        return listingId;
    }

    function getActiveListings(uint256 _startIndex, uint256 _count) public view returns (Listing[] memory, bool) {
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
    //gibt das Array von Listing struct zurück und einen boolean, ob noch mehr Listings existieren
        return (result, endIndex < totalActive);
    }

    function getListingDetailsFromId(uint256 _listingId) external view returns (
        address seller, 
        address tokenContract,
        uint256 tokenId, 
        uint256 price, 
        uint256 quantity) {
        Listing storage listing = listings[_listingId];
        return (listing.seller, listing.tokenContract, listing.tokenId, listing.price, listing.quantity);
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
        uint256[] storage sellerListingIds = sellerListings[_seller];
        for (uint i = 0; i < sellerListingIds.length; i++) {
            if (sellerListingIds[i] == _listingId) {
                sellerListingIds[i] = sellerListingIds[sellerListingIds.length - 1];
                sellerListingIds.pop();
                break;
            }
        }
    }

    function _removeFromAssignTokenToListings(address _tokenContract, uint256 _tokenId, uint256 _listingId) internal {
        uint256[] storage tokenListings = assignTokenToListings[_tokenContract][_tokenId];
        for (uint i = 0; i < tokenListings.length; i++) {
            if (tokenListings[i] == _listingId) {
                tokenListings[i] = tokenListings[tokenListings.length - 1];
                tokenListings.pop();
                break;
            }
        }
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

//Listing Utils
    function _getNextListingId() private returns (uint256) {
    listingCounter++;
    return listingCounter;
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