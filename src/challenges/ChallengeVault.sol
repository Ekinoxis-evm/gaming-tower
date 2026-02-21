// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IIdentityNFT} from "./IIdentityNFT.sol";

/// @title ChallengeVault
/// @notice EIP-4626 escrow vault for two-player token challenges.
/// @dev Each vault handles one challenge. Player1 is set at creation (identity
///      checked at VaultFactory); Player2 joins by depositing and must also
///      hold a valid IdentityNFT. After the challenge window ends, both players
///      submit a number — highest number wins. The resolver breaks ties.
///      Shares are non-transferable (soulbound to players).
contract ChallengeVault is ERC4626, Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ── Types ────────────────────────────────────────────────────────────────

    enum State { OPEN, ACTIVE, RESOLVED, CANCELLED }

    // ── Storage ──────────────────────────────────────────────────────────────

    uint256      public immutable stakeAmount;
    uint256      public immutable challengeDuration;
    IIdentityNFT public immutable identityNFT;

    string  public metadataURI;
    address public resolver;

    address public player1;
    address public player2;
    State   public state;
    uint256 public endTime;
    address public winner;

    mapping(address => uint256) public submittedNumber;
    mapping(address => bool)    public hasSubmitted;

    // ── Events ───────────────────────────────────────────────────────────────

    event PlayerJoined(address indexed player);
    event ChallengeActivated(uint256 endTime);
    event NumberSubmitted(address indexed player, uint256 number);
    event ChallengeResolved(address indexed winner, uint256 prize);
    event ChallengeCancelled();
    event ResolverUpdated(address indexed newResolver);

    // ── Errors ───────────────────────────────────────────────────────────────

    error NotPlayer();
    error WrongState();
    error AlreadyJoined();
    error WrongStakeAmount();
    error SharesNonTransferable();
    error NotResolver();
    error NoActiveIdentity();
    error NotAfterEndTime();
    error AlreadySubmitted();
    error BothMustSubmit();

    // ── Constructor ──────────────────────────────────────────────────────────

    /// @param _token        The ERC-20 token used for staking.
    /// @param _stakeAmount  Amount each player must stake (token wei).
    /// @param _duration     Challenge duration in seconds.
    /// @param _metadataURI  IPFS URI describing the challenge.
    /// @param _resolver     Trusted address that breaks ties.
    /// @param _player1      Creator / first player address.
    /// @param _identityNFT  Identity contract — player2 must pass isValid().
    constructor(
        IERC20  _token,
        uint256 _stakeAmount,
        uint256 _duration,
        string  memory _metadataURI,
        address _resolver,
        address _player1,
        address _identityNFT
    )
        ERC4626(_token)
        ERC20("ChallengeVault Share", "CVS")
        Ownable(msg.sender)
    {
        stakeAmount       = _stakeAmount;
        challengeDuration = _duration;
        metadataURI       = _metadataURI;
        resolver          = _resolver;
        player1           = _player1;
        identityNFT       = IIdentityNFT(_identityNFT);
        state             = State.OPEN;
    }

    // ── ERC-4626 overrides ───────────────────────────────────────────────────

    /// @dev 1-to-1 ratio: no yield accrual, no inflation-attack offset needed.
    function _convertToShares(uint256 assets, Math.Rounding)
        internal
        view
        override
        returns (uint256)
    {
        return assets;
    }

    function _convertToAssets(uint256 shares, Math.Rounding)
        internal
        view
        override
        returns (uint256)
    {
        return shares;
    }

    /// @dev Gate deposits: only two players, exact stake amount, correct state.
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal override {
        if (state != State.OPEN)        revert WrongState();
        if (assets != stakeAmount)      revert WrongStakeAmount();

        if (receiver == player1) {
            if (balanceOf(player1) > 0) revert AlreadyJoined();
        } else {
            // Player2 must hold a valid (active, non-suspended) IdentityNFT.
            if (!identityNFT.isValid(receiver)) revert NoActiveIdentity();
            if (player2 != address(0))          revert AlreadyJoined();
            player2 = receiver;
        }

        super._deposit(caller, receiver, assets, shares);
        emit PlayerJoined(receiver);

        // Activate once both players have deposited
        if (player2 != address(0) && balanceOf(player1) > 0 && balanceOf(player2) > 0) {
            state   = State.ACTIVE;
            endTime = block.timestamp + challengeDuration;
            emit ChallengeActivated(endTime);
        }
    }

    /// @dev Standard ERC-4626 withdraw/redeem are disabled; use submitNumber to resolve.
    function _withdraw(address, address, address, uint256, uint256)
        internal
        pure
        override
    {
        revert("Use submitNumber to resolve");
    }

    /// @dev Shares are soulbound — prevent player-to-player transfers.
    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) revert SharesNonTransferable();
        super._update(from, to, value);
    }

    /// @dev Public deposit with reentrancy + pause guards.
    function deposit(uint256 assets, address receiver)
        public
        override
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        return super.deposit(assets, receiver);
    }

    /// @dev max* overrides keep ERC-4626 views consistent with vault logic.
    function maxDeposit(address account) public view override returns (uint256) {
        if (state != State.OPEN) return 0;
        if (account == player1 && balanceOf(player1) > 0) return 0;
        if (account != player1 && player2 != address(0)) return 0;
        return stakeAmount;
    }

    function maxMint(address account) public view override returns (uint256) {
        return maxDeposit(account);
    }

    function maxWithdraw(address) public pure override returns (uint256) { return 0; }
    function maxRedeem(address)   public pure override returns (uint256) { return 0; }

    // ── Challenge logic ──────────────────────────────────────────────────────

    /// @notice Submit your number after the challenge window ends.
    ///         Highest number wins. Resolver breaks ties.
    function submitNumber(uint256 number) external nonReentrant {
        if (state != State.ACTIVE)                                 revert WrongState();
        if (block.timestamp < endTime)                             revert NotAfterEndTime();
        if (msg.sender != player1 && msg.sender != player2)       revert NotPlayer();
        if (hasSubmitted[msg.sender])                              revert AlreadySubmitted();

        submittedNumber[msg.sender] = number;
        hasSubmitted[msg.sender]    = true;
        emit NumberSubmitted(msg.sender, number);

        // Auto-resolve when both have submitted
        if (hasSubmitted[player1] && hasSubmitted[player2]) {
            uint256 n1 = submittedNumber[player1];
            uint256 n2 = submittedNumber[player2];
            if (n1 > n2) {
                _resolveChallenge(player1);
            } else if (n2 > n1) {
                _resolveChallenge(player2);
            }
            // Tie: leave state ACTIVE, resolver must call resolveDispute()
        }
    }

    /// @notice Resolver breaks a tie (only callable when both submitted the same number).
    function resolveDispute(address _winner) external nonReentrant {
        if (msg.sender != resolver)                                  revert NotResolver();
        if (state != State.ACTIVE)                                   revert WrongState();
        if (!hasSubmitted[player1] || !hasSubmitted[player2])        revert BothMustSubmit();
        require(submittedNumber[player1] == submittedNumber[player2], "Not a tie");

        _resolveChallenge(_winner);
    }

    // ── Internal resolution ──────────────────────────────────────────────────

    function _resolveChallenge(address _winner) internal {
        winner = _winner;
        state  = State.RESOLVED;

        uint256 prize = balanceOf(player1) + balanceOf(player2);

        _burn(player1, balanceOf(player1));
        _burn(player2, balanceOf(player2));

        IERC20(asset()).safeTransfer(_winner, prize);
        emit ChallengeResolved(_winner, prize);
    }

    // ── Admin ────────────────────────────────────────────────────────────────

    function setResolver(address _resolver) external onlyOwner {
        resolver = _resolver;
        emit ResolverUpdated(_resolver);
    }

    function pause()   external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }
}
