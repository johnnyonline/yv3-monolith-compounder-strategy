// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.23;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {BaseStrategy} from "@tokenized-strategy/BaseStrategy.sol";
import {TokenizedStrategyLib as TokenizedStrategy} from "@tokenized-strategy/libraries/TokenizedStrategyLib.sol";
import {BaseHealthCheck, ERC20} from "@periphery/Bases/HealthCheck/BaseHealthCheck.sol";
import {BaseSwapper} from "@periphery/swappers/BaseSwapper.sol";
import {IAuction} from "@periphery/interfaces/IAuction.sol";
import {AuctionFactory} from "@periphery/Auctions/AuctionFactory.sol";

import {IStakedGovToken} from "./interfaces/IStakedGovToken.sol";

contract MonolithCompounder is BaseSwapper, BaseHealthCheck {

    using SafeERC20 for ERC20;

    // ===============================================================
    // Constants
    // ===============================================================

    /// @notice Idle `asset` below this isn't worth the gas to stake
    uint256 internal constant _DUST_AMOUNT = 1e18;

    /// @notice Coin the staked gov token earns, e.g. swanUSD
    address public immutable REWARDS_TOKEN;

    /// @notice Auction selling rewards for `asset`, governed by this strategy
    // forge-lint: disable-next-line(screaming-snake-case-immutable)
    IAuction public immutable auction;

    /// @notice Staked gov token `asset` is staked in, e.g. sSWAN
    IStakedGovToken public immutable STAKING;

    /// @notice Yearn AuctionFactory v1.0.5, so taker bots can discover the auction
    AuctionFactory public constant AUCTION_FACTORY = AuctionFactory(0x55B3830B4D85e6868c73f00A2e857e9AdbF89568);

    // ===============================================================
    // Constructor
    // ===============================================================

    /// @param _asset Address of the gov token, e.g. SWAN
    /// @param _name Name of the strategy
    /// @param _staking Address of the staked gov token, e.g. sSWAN
    constructor(
        address _asset,
        string memory _name,
        address _staking
    ) BaseHealthCheck(_asset, _name) {
        STAKING = IStakedGovToken(_staking);
        require(STAKING.underlying() == _asset, "!staking");
        REWARDS_TOKEN = STAKING.rewardsToken();

        // Let the staked gov token pull `asset`
        asset.forceApprove(_staking, type(uint256).max);

        // Rewards are sold for `asset` in our own auction. Only we can kick it
        auction = IAuction(AUCTION_FACTORY.createNewAuction(_asset, address(this), address(this)));
        auction.enable(REWARDS_TOKEN);
        auction.setGovernanceOnlyKick(true);
    }

    // ===============================================================
    // View functions
    // ===============================================================

    /// @notice Idle `asset` held by the strategy
    /// @return Amount of `asset`
    function balanceOfAsset() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    /// @notice `asset` staked in the staked gov token
    /// @return Amount of staked `asset`
    function balanceOfStake() public view returns (uint256) {
        return STAKING.balanceOf(address(this));
    }

    /// @notice Claimed rewards waiting to be auctioned
    /// @return Amount of `REWARDS_TOKEN`
    function balanceOfRewards() public view returns (uint256) {
        return ERC20(REWARDS_TOKEN).balanceOf(address(this));
    }

    /// @notice Rewards earned but not yet claimed
    /// @return Amount of `REWARDS_TOKEN`
    function claimableRewards() external view returns (uint256) {
        return STAKING.earned(address(this));
    }

    // ===============================================================
    // Management functions
    // ===============================================================

    /// @notice Set the min amount of a token to auction
    /// @param _token Token to set the min for
    /// @param _minAmountToSell Min amount of `_token`
    function setMinAmountToSell(
        address _token,
        uint256 _minAmountToSell
    ) external onlyManagement {
        _setMinAmountToSell(_token, _minAmountToSell);
    }

    /// @notice Enable auctioning a token and set its min amount
    /// @dev Useful for selling tokens sent to the strategy by mistake
    /// @param _token Token to enable
    /// @param _minAmountToSell Min amount of `_token`
    function enableAuctionToken(
        address _token,
        uint256 _minAmountToSell
    ) external onlyManagement {
        require(_token != address(asset), "!asset");
        auction.enable(_token);
        _setMinAmountToSell(_token, _minAmountToSell);
    }

    /// @notice Set the auction's price floor
    /// @dev Reverts while an auction is live
    /// @param _minimumPrice Min price in `asset` per token sold, WAD scaled
    function setMinimumAuctionPrice(
        uint256 _minimumPrice
    ) external onlyManagement {
        auction.setMinimumPrice(_minimumPrice);
    }

    /// @notice Set the auction's opening price
    /// @dev Reverts while an auction is live
    /// @param _startingPrice Opening price of a whole lot in `asset`, WAD scaled
    function setAuctionStartingPrice(
        uint256 _startingPrice
    ) external onlyManagement {
        auction.setStartingPrice(_startingPrice);
    }

    /// @notice Set the auction's price decay
    /// @dev Reverts while an auction is live
    /// @param _stepDecayRate Decay per step in basis points
    function setAuctionStepDecayRate(
        uint256 _stepDecayRate
    ) external onlyManagement {
        auction.setStepDecayRate(_stepDecayRate);
    }

    /// @notice Delegate the strategy's votes
    /// @param _delegatee Address to delegate to
    function delegate(
        address _delegatee
    ) external onlyManagement {
        STAKING.delegate(_delegatee);
    }

    // ===============================================================
    // Keeper functions
    // ===============================================================

    /// @notice Claim rewards without auctioning them
    function claimRewards() external onlyKeepers {
        _claimRewards();
    }

    /// @notice Kick an auction selling a token for `asset`
    /// @dev Claims rewards first when kicking `REWARDS_TOKEN`. Noop at or below `minAmountToSell`
    /// @param _token Token to sell
    function kickAuction(
        address _token
    ) external onlyKeepers {
        if (_token == REWARDS_TOKEN) _claimRewards();
        uint256 _balance = ERC20(_token).balanceOf(address(this));
        if (_balance > minAmountToSell[_token]) _kickAuction(_token, _balance);
    }

    // ===============================================================
    // Internal mutated functions
    // ===============================================================

    /// @inheritdoc BaseStrategy
    function _deployFunds(
        uint256 _amount
    ) internal override {
        STAKING.depositFor(address(this), _amount);
    }

    /// @inheritdoc BaseStrategy
    function _freeFunds(
        uint256 _amount
    ) internal override {
        STAKING.withdrawTo(address(this), _amount);
    }

    /// @inheritdoc BaseStrategy
    function _harvestAndReport() internal override returns (uint256) {
        // Claim rewards and put them up for auction
        _claimRewards();
        uint256 _rewards = balanceOfRewards();
        if (_rewards > minAmountToSell[REWARDS_TOKEN]) _kickAuction(REWARDS_TOKEN, _rewards);

        // Stake idle `asset`
        uint256 _balance = balanceOfAsset();
        if (!TokenizedStrategy.isShutdown() && _balance > _DUST_AMOUNT) _deployFunds(_balance);

        // Staked 1:1
        return balanceOfAsset() + balanceOfStake();
    }

    /// @inheritdoc BaseStrategy
    function _emergencyWithdraw(
        uint256 _amount
    ) internal override {
        _freeFunds(Math.min(_amount, balanceOfStake()));
    }

    /// @notice Push pending revenue to the staked gov token and claim our share
    function _claimRewards() internal {
        STAKING.harvestAndGetReward();
    }

    /// @notice Send a token to the auction and kick it
    /// @dev Noop while the last auction of the token still has some left
    /// @param _token Token to sell
    /// @param _balance Amount of `_token` to add to the lot
    function _kickAuction(
        address _token,
        uint256 _balance
    ) internal {
        require(_token != address(asset), "!asset");

        if (auction.isActive(_token)) {
            if (auction.available(_token) > 0) return;
            auction.settle(_token);
        }

        ERC20(_token).safeTransfer(address(auction), _balance);
        auction.kick(_token);
    }

}
