// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;                              // Certik DCK-01

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract DebloxNFT is ERC721Enumerable, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    using Strings for uint256;

    string private _URI;                        // Certik DNF-04
    string public baseExtension = ".json";
    string public PROVENANCE;
    
    uint256 public price;
    uint256 public maxSupply;
    uint256 public maxMint;
    uint256 public addressLimit;                 // Certik DNF-05

    bool public sale = false;
    bool public locked = false;
    bool private reserved = false;
    uint256 public rNFT;
    
    bool public revealed = false;
    string public nonURI;

    bool public onlyWL;
    mapping(address => bool) public wlAddr;
    mapping(address => uint256) public addrMinted;

    event Base();
    event Reveal();
    event Price();
    event Non();
    event Limit();
    event MintLimit();
    event MaxSupply();
    event FlipSale();
    event FR();
    event FlipWL();
    event LockMD();
    event Add(address indexed entry);
    event Remove(address indexed entry);
    event Reserve();
    event Withdraw(uint256 balance);

    modifier notLocked {
        require(!locked, "NA9");
        _;
    }
    
    constructor(
        string memory _name,
        string memory _symbol,
        string memory _RU,
        string memory _NRU,
        bool _OWL,
        uint256 _r
    ) ERC721(_name, _symbol) {
        setBaseURI(_RU);
        setNotRevealedURI(_NRU);
        onlyWL = _OWL;
        rNFT = _r;
    }
    
    function setBaseURI(string memory URI) public onlyOwner notLocked {
        _URI = URI;
        emit Base();
    }
    
    function reveal() public onlyOwner {
        require(!sale, "NC1");
        revealed = true;
        emit Reveal();
    }
  
    function setPrice(uint256 _c) public onlyOwner {
        require(!sale, "NC2");
        price = _c;
        emit Price();
    }
  
    function setNotRevealedURI(string memory _NRU) public onlyOwner {
        require(!sale, "NC3");
        nonURI = _NRU;
        emit Non();
    }
    
    function setAddressLimit(uint256 _l) public onlyOwner {
        require(!sale, "NC4");
        addressLimit = _l;
        emit Limit();
    }
    
    function setMaxMint(uint256 _l) public onlyOwner {
        require(!sale, "NC5");
        maxMint = _l;
        emit MintLimit();
    }
    
    function setMaxSupply(uint256 _l) public onlyOwner {
        require(!sale, "NC6");
        maxSupply = _l;
        emit MaxSupply();
    }
    
    function flipSaleState() public onlyOwner {
        sale = !sale;
        emit FlipSale();
    }
    
    // This function is only used for exceptional scenario
    function flipReserved() public onlyOwner {
        reserved = !reserved;
        emit FR();
    }
  
    function flipWhitelisted() public onlyOwner {
        require(!sale, "NC7");
        onlyWL = !onlyWL;
        emit FlipWL();
    }
    
    // Owner functions for enabling presale, sale, revealing and setting the provenance hash
    function lockMetadata() external onlyOwner {
        locked = true;
        emit LockMD();
    }
    
    function addToWhiteList(address[] calldata _e) external onlyOwner {
        for(uint256 i = 0; i < _e.length; i++) {
            address entry = _e[i];
            require(entry != address(0), "NA0");
            wlAddr[entry] = true;
            emit Add(entry);
        }   
    }

    function removeFromWhiteList(address[] calldata _e) external onlyOwner {
        for(uint256 i = 0; i < _e.length; i++) {
            address entry = _e[i];
            require(entry != address(0), "NA0");
            wlAddr[entry] = false;
            emit Remove(entry);
        }
    }
    
    /**
     * @dev One time reserve function
     * And the reserved amount can be only set when contract is created
     */
    function reserve() public onlyOwner {
        require(!reserved, "NA1");

        reserved = true;

        uint i;
        for (i = 0; i < rNFT; i++) {    
            _tokenIds.increment();
            uint256 newItemId = _tokenIds.current();

            addrMinted[msg.sender]++;
            _safeMint(msg.sender, newItemId);
        }

        emit Reserve();
    }

    /**
     * @dev To mint given mint amount of NFT
     */
    function mint(uint256 _a) external payable {
        require(sale, "NA2");
        require(_a > 0, "NA3");
        require(_a <= maxMint, "NA4");
        require(price * _a <= msg.value, "NA5");
        uint256 supply = totalSupply();
        require(supply + _a <= maxSupply, "NA6");

        uint256 ownerMintedCount = addrMinted[msg.sender];
        require(ownerMintedCount + _a <= addressLimit, "NA7");
        
        if(onlyWL == true) {
            require(wlAddr[msg.sender], "NA8");
        }

        for (uint256 i = 1; i <= _a; i++) {
            _tokenIds.increment();
            uint256 newItemId = _tokenIds.current();

            addrMinted[msg.sender]++;
            _safeMint(msg.sender, newItemId);
        }
    }

    function withdraw() public onlyOwner {
        (bool os, ) = payable(owner()).call{value: address(this).balance}("");
        require(os);

        emit Withdraw(address(this).balance);
    }

    // internal
    function _baseURI() internal view virtual override returns (string memory) {
        return _URI;
    }
    
    // View functions
    function isWhitelisted(address _a) external view returns (bool) {
        return wlAddr[_a];
    }

    function walletOfOwner(address _owner)
        public
        view
        returns (uint256[] memory)
    {
        uint256 c = balanceOf(_owner);
        uint256[] memory tokenIds = new uint256[](c);
        for (uint256 i; i < c; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(_owner, i);
        }
        return tokenIds;
    }

    function currentId() external view returns (uint256) {
        return _tokenIds.current();
    }
    
    function getSaleStatus() external view returns (bool) {
        return sale;
    }
    
    function tokenURI(uint256 _t) public view override returns (string memory) {
        require(_exists(_t), "NC8");
    
        if(revealed == false) {
            return nonURI;
        }

        string memory u = _baseURI();
        return bytes(u).length > 0
            ? string(abi.encodePacked(u, _t.toString(), baseExtension))
            : "";
        }

}
