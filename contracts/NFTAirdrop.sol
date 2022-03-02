// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.6.12;                         // Certik DCK-01

import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract NFTAirdrop is Ownable {
    using SafeBEP20 for IBEP20;

    IERC721 internal immutable nft;
    IBEP20 public tokenToClaim;
    uint256 public immutable tokensPerClaim;

    event Claimed(uint256 indexed tokenId, address indexed claimer);
    event FlipClaimState();

    mapping(uint256 => bool) public hasClaimed;
    bool public claimable = false;

    constructor(
        address _nft,                                                         // Certik NFT-04
        address _tokenToClaim,
        uint256 _tokensPerClaim
    ) public {
        require(_nft != address(0), "_nft is a zero address");                 // Certik NFT-04
        require(_tokenToClaim != address(0), "_tokenToClaim is a zero address");

        nft = IERC721(_nft);
        tokenToClaim = IBEP20(_tokenToClaim);
        tokensPerClaim = _tokensPerClaim;
    }
    
    function flipClaimState() public onlyOwner {
        claimable = !claimable;
        emit FlipClaimState();                          // Certik NFT-03
    }

    function claim(uint256 tokenId) external {                               // Certik Unncessary payable Modifier
        require(claimable, "Claim is not available!");
        require(_balance() > 0, "Run out of tokens, please contact admin");
        
        require(!hasClaimed[tokenId], "Already claimed");
        require(nft.ownerOf(tokenId) == msg.sender, "Not onwer");

        hasClaimed[tokenId] = true;
        emit Claimed(tokenId, msg.sender);

        tokenToClaim.safeTransfer(msg.sender, tokensPerClaim);
    }

    function batchClaim(uint256[] memory tokenIds) external {                // Certik Unncessary payable Modifier
        require(claimable, "Claim is not available!");
        require(_balance() > 0, "Run out of tokens, please contact admin");

        for (uint256 index = 0; index < tokenIds.length; index++) {
            uint256 tokenId = tokenIds[index];

            require(!hasClaimed[tokenId], "Already claimed");
            require(nft.ownerOf(tokenId) == msg.sender, "Not onwer");

            hasClaimed[tokenId] = true;
            emit Claimed(tokenId, msg.sender);
        }

        tokenToClaim.safeTransfer(msg.sender, tokensPerClaim * tokenIds.length);
    }

    function claimableTokenIds(uint256[] memory tokenIds)
        public
        view
        returns (uint256[] memory)
    {
        uint256 length = tokenIds.length;
        uint256[] memory claimableIds = new uint256[](length);
        for (uint256 i; i < length; i++) {
            uint256 tokenId = tokenIds[i];
            if(!hasClaimed[tokenId]) {
                claimableIds[i] = tokenId;
            }
        }
        return claimableIds;
    }

    function balance() public view returns (uint256) {
        return _balance();
    }

    function _balance() internal view returns (uint256) {
        return tokenToClaim.balanceOf(address(this));
    }
}
