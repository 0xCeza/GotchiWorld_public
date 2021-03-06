// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Receiver.sol";

/**
 * @dev Contains the interact() function currently used to pet gotchis
 * Contract will need to be updated when pet() & petOperator are added to the game 
 */
interface IAavegotchiGameFacet {
    function interact(uint256[] calldata _tokenIds) external;
    function isApprovedForAll(address _owner, address _operator) external view returns (bool approved_);
}

/**
 * @dev used to stake, unstake, keep track of frens and claim tickets
 */
interface IStakingFacet {
    function frens(address _account) external view returns (uint256 frens_);
    function stakeGhst(uint256 _ghstValue) external;
    function withdrawGhstStake(uint256 _ghstValue) external;
    function claimTickets(uint256[] calldata _ids, uint256[] calldata _values) external;
}

/**
 * @dev used to transfer tickets 
 */
interface ITicketsFacet {
    function safeBatchTransferFrom(address _from,address _to,uint256[] calldata _ids,uint256[] calldata _values,bytes calldata _data) external;
    function balanceOfAll(address _owner) external view returns (uint256[] memory balances_);
    function setApprovalForAll(address _operator, bool _approved) external;
}

/**
 * @dev Used to transfer GHST ERC20 Token (equi. IERC20)
 */
interface IGHSTFacet {
    function transferFrom(address _from,address _to,uint256 _value) external returns (bool success);
    function approve(address _spender, uint256 _value) external returns (bool success);
    function transfer(address _to, uint256 _value) external returns (bool success);
    function balanceOf(address _owner) external view returns (uint256 balance);
}

contract Nursery is Ownable, ERC1155Receiver {
    
    event PetThemAll(uint256[] _gotchiIds);
    event AddMember(address _newMember);
    event RemoveMember(address _betrayer);
    
    uint256 private constant MAX_INT = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    uint256 private constant STAKING_FEES = 10 ** 18;
    uint256 private constant STAKING_AMOUNT = 69 * 10 ** 18;
    
    // Petting 
    address[] private _members;
    uint256 private ctTotalPets;
    // Staking 
    uint256 private _collectedFees;
    
    // Contract addresses
    address public diamond;
    address public ghstDiamond;
    address public ghstERC20;
    
    // Interfaces to Aavegotchi contract - Petting 
    IAavegotchiGameFacet private immutable gameFacet;
    
    // Interfaces to Aavegotchi contract - Staking
    IStakingFacet private immutable stakingFacet;
    ITicketsFacet private immutable ticketsFacet;
    IGHSTFacet private immutable ghstFacet;
    
    // Mapping used to know the index of a member in the _members array
    // (memeber address => index id)
    mapping (address => uint256) public index;
    
    // Mapping used to know the current balance in Ghst 
    // (address owner => value)
    mapping (address => uint256) private _balances;

    constructor(address _diamond, address _ghstDiamond, address _ghstERC20) {
        diamond = _diamond;
        ghstDiamond = _ghstDiamond;
        ghstERC20 = _ghstERC20;
        // Petting 
        gameFacet = IAavegotchiGameFacet(diamond); // is immutable
        ctTotalPets = 0;
        _members.push(address(0)); // first member is address 0 and index of leavers
        // Staking 
        stakingFacet = IStakingFacet(ghstDiamond); // is immutable
        ticketsFacet = ITicketsFacet(ghstDiamond); // is immutable
        ghstFacet = IGHSTFacet(ghstERC20);         // is immutable
    }
    
    /************************************************
     * 
     *   USERS FUNCTIONS  
     * 
     ************************************************/
     
    /**
     * @notice Simple staking. You can only stake the STAKING_AMOUNT and that's it. Can't stake twice.
     */
    function stakeGhst() external {
        // Make sure member is not already staking (saving you 1GHST fees from mistakes)
        require(_balances[msg.sender] == 0, "Already staking");
        
        // Get the ghst from the account to the contract 
        ghstFacet.transferFrom(msg.sender, address(this), STAKING_AMOUNT);
        
        // Remove 1 GHST in staking fees that is added to the _collectedFees
        uint256 _stkValue = STAKING_AMOUNT - STAKING_FEES;
        _collectedFees += STAKING_FEES;
        
        // Stake from the contract to collect Frens 
        stakingFacet.stakeGhst(_stkValue);

        // Update the Balance of the msgsender 
        _balances[msg.sender] += _stkValue;
        
        // Add to the member array 
        _addMember(msg.sender);
    }
    
    /**
     * @notice Simple unstaking. You don't choose the amount, it unstake your balance 
     */
    function unstakeGhst() external {
        // Check if the account has enough ghst staked
        require(_balances[msg.sender] > 0, "Can't withdraw nothing");
        
        // Save balance of msgsender
        uint256 tempBalance = _balances[msg.sender];
        
        // Update the balance of msgsender  
        _balances[msg.sender] = 0;
        
        // Unstake from the contract 
        stakingFacet.withdrawGhstStake(tempBalance);
    
        // Send back the ghst to the msgsender
        ghstFacet.transfer(msg.sender, tempBalance);
        
        // Remove from member array
        _removeMember(msg.sender);
    }
    
    /************************************************
     * 
     *   BOT FUNCTIONS  
     * 
     ************************************************/
    
    /**
     * @dev Max 100 _gotchiIds per tx (like Pet All Function)
     */ 
    function petThemAll(uint256[] calldata _gotchiIds) external onlyOwner {
        // Interact with all the gotchis to pet
        gameFacet.interact(_gotchiIds);

        // Count how many gotchis this contract has ever pet
        ctTotalPets += _gotchiIds.length;
        
        emit PetThemAll(_gotchiIds);
    }
    
    /************************************************
     * 
     *   ADMIN FUNCTIONS - STAKING  
     * 
     ************************************************/
    
    /**
     * @dev claim tickets then sends them to the owner. No this doesnt transfer your gotchi kek 
     */
    function claimTicketsAndWithdraw(uint256[] calldata _ids, uint256[] calldata _values) external onlyOwner {
        stakingFacet.claimTickets(_ids, _values);
        ticketsFacet.safeBatchTransferFrom(address(this), owner(), _ids, _values, "");
    }
    
    /**
     * @dev Withdraw collected 1 GHST Staking Fees
     */
    function withdrawCollectedFees() external onlyOwner {
        // tempCollectedFees prevent from calling multiple times the function to withdraw more ghst
        // This is not that useful as this contract doesn't have more than collected fees at any time
        uint256 tempCollectedFees = _collectedFees;
        _collectedFees = 0;
        ghstFacet.transfer(owner(), tempCollectedFees);
    }
    
    /**
     * @dev to be called during deploy, used to allow staking GHST in the main Aavegotchi contract
     */
    function approveGhst() external onlyOwner returns (bool) {
        return ghstFacet.approve(ghstDiamond,MAX_INT);
    }

    /************************************************
     * 
     *   PRIVATE FUNCTIONS - PETTING 
     * 
     ************************************************/
    
    /**
     * @dev Array used internaly to list all the accounts to pet. Called by stakeGhst()
     */
    function _addMember(address _newMember) private {
        // No need to add twice the same account
        require(index[_newMember] == 0,"Member already added");

        // Get the index where the new member is in the array 
        index[_newMember] = _members.length;

        // Push the data in the array 
        _members.push(_newMember);
        
        emit AddMember(_newMember);
    }
    
    /**
     * @dev Remove member, index it to 0, remove gaps. Called by unstakeGhst()
     */
    function _removeMember(address _betrayer) private {
        // Cant remove an account that is not a member
        require(index[_betrayer] != 0,"Member already removed");

        // Get the index of the betrayer in the array 
        uint256 _index = index[_betrayer];
        
        // Get last element in array
        uint256 lastElementIndex = _members.length - 1;
        
        // Take the last entry in the array and add it in the betrayers index
        _members[_index] = _members[lastElementIndex];
        
        // Remove last entry in the array and reduce length
        _members.pop();
        index[_betrayer] = 0;
        
        // this guy is ngmi 
        emit RemoveMember(_betrayer);
    }
    
    /************************************************
     * 
     *   VIEWS FUNCTION - PETTING 
     * 
     ************************************************/
     
    function getMembers() external view returns (address[] memory) {
        return _members;
    }
    
    function getTotalPets() public view returns (uint256) {
        return ctTotalPets;
    }
    
    function hasApprovedGotchiInteraction(address _account) public view returns (bool) {
        return gameFacet.isApprovedForAll(_account,address(this));
    }
    
    /************************************************
     * 
     *   VIEWS FUNCTION - STAKING 
     * 
     ************************************************/
     
    function hasStaked(address _account) public view returns (bool) {
        return _balances[_account] == (STAKING_AMOUNT - STAKING_FEES);
    }
    
    function hasMembership(address _account) public view returns (bool) {
        return index[_account] > 0;
    }
    
    function collectedFees() external view returns (uint256) {
        return _collectedFees;
    }
    
    function stakingFees() external pure returns (uint256) {
        return STAKING_FEES;
    }
    
    function stakingAmount() external pure returns (uint256) {
        return STAKING_AMOUNT;
    }
    
    function stakedAmount() external view returns (uint256) {
        return _balances[msg.sender];
    }
    
    function contractFrensBalance() external view returns (uint256) {
        return stakingFacet.frens(address(this));
    }
        
    /************************************************
     * 
     *   VIEWS FUNCTION - BOTH 
     * 
     ************************************************/
     
    function shouldPet(address _member) external view returns (bool) {
        if(hasApprovedGotchiInteraction(_member) && hasStaked(_member) && hasMembership(_member)) {
            return true;
        }
        return false;
    }
    
    /************************************************
     * 
     *   ERC1155Receiver 
     * 
     ************************************************/
    /**
     * @dev both function in ERC1155Receiver are used so that the contract can own ERC1155 tokens
     */
    function onERC1155Received(
    address /*operator*/,
    address /*from*/,
    uint256 /*id*/,
    uint256 /*value*/,
    bytes calldata /*data*/
    )
    external
    pure
    override
    returns(bytes4)
    {
        return bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"));
    }

    function onERC1155BatchReceived(
    address /*operator*/,
    address /*from*/,
    uint256[] calldata /*ids*/,
    uint256[] calldata /*values*/,
    bytes calldata /*data*/
    )
    external
    pure
    override
    returns(bytes4)
    {
        return bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"));
    }
}
