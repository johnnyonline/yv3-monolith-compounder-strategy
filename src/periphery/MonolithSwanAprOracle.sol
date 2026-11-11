// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {AprOracleBase} from "@periphery/AprOracle/AprOracleBase.sol";

import {ISUSDS} from "../interfaces/ISUSDS.sol";
import {IStakedGovToken} from "../interfaces/IStakedGovToken.sol";
import {IStrategyInterface} from "../interfaces/IStrategyInterface.sol";
import {IUniswapV4StateView} from "../interfaces/IUniswapV4StateView.sol";
import {IMonolithLender, IRevenueRouter} from "../interfaces/IMonolith.sol";

contract MonolithSwanAprOracle is AprOracleBase {

    // ===============================================================
    // Storage
    // ===============================================================

    /// @notice Addresses besides governance that can set manual prices
    mapping(address keeper => bool allowed) public keepers;

    /// @notice Uniswap V4 pool pricing each strategy's rewards in `asset`
    mapping(address strategy => bytes32 poolId) public poolIds;

    /// @notice Manual price of each strategy's rewards in `asset`, WAD scaled. Used instead of the pool when nonzero
    mapping(address strategy => uint256 price) public manualPrices;

    // ===============================================================
    // Constants
    // ===============================================================

    /// @notice WAD constant
    uint256 private constant _WAD = 1e18;

    /// @notice RAY constant
    uint256 private constant _RAY = 1e27;

    /// @notice Max basis points
    uint256 private constant _MAX_BPS = 10_000;

    /// @notice Seconds in a year
    uint256 private constant _SECONDS_PER_YEAR = 365 days;

    /// @notice Uniswap V4 StateView
    IUniswapV4StateView public constant STATE_VIEW = IUniswapV4StateView(0x7fFE42C4a5DEeA5b0feC41C94C136Cf115597227);

    // ===============================================================
    // Constructor
    // ===============================================================

    /// @param _governance Address that sets the pools and keepers
    constructor(
        address _governance
    ) AprOracleBase("Monolith SWAN APR Oracle", _governance) {}

    // ===============================================================
    // Modifiers
    // ===============================================================

    modifier onlyKeepers() {
        require(msg.sender == governance || keepers[msg.sender], "!keeper");
        _;
    }

    // ===============================================================
    // View functions
    // ===============================================================

    /// @inheritdoc AprOracleBase
    /// @dev Like the Monolith UI: the stakers' share of the market's current yearly revenue,
    /// priced in `asset` and spread over the staked supply after `_delta`
    function aprAfterDebtChange(
        address _strategy,
        int256 _delta
    ) external view override returns (uint256) {
        IStakedGovToken _staking = IStakedGovToken(IStrategyInterface(_strategy).STAKING());
        IRevenueRouter _router = IRevenueRouter(_staking.revenueRouter());

        // Staked supply after the debt change
        uint256 _supply = _staking.totalSupply();
        if (_delta < 0) require(uint256(-_delta) < _supply, "!delta");
        uint256 _newSupply = uint256(int256(_supply) + _delta);
        if (_newSupply == 0) return 0;

        // Stakers' share of the yearly revenue, in `asset`
        return revenue(_router.lender()) * _router.govStakingBps() / _MAX_BPS * price(_strategy) / _newSupply;
    }

    /// @notice A market's current yearly revenue
    /// @dev Interest kept as local reserves plus the PSM's sUSDS yield, both at today's rates
    /// @param _lender Lender of the market
    /// @return _revenue Yearly revenue in the market's coin
    function revenue(
        address _lender
    ) public view returns (uint256 _revenue) {
        IMonolithLender _l = IMonolithLender(_lender);

        // Local reserve fee on the interest paid debt pays
        uint256 _paidDebt = _l.totalPaidDebt();
        uint256 _interest = _paidDebt * _l.lastBorrowRateMantissa() / _WAD;
        _revenue = _interest * _l.feeBps() / _MAX_BPS;

        // Plus the interest savers can't take when they stake less than the paid debt
        uint256 _staked = IERC20(_l.coin()).balanceOf(_l.vault());
        if (_staked < _paidDebt) {
            uint256 _afterFees = _interest - _revenue - _interest * _l.cachedGlobalFeeBps() / _MAX_BPS;
            _revenue += _afterFees - _afterFees * _staked / _paidDebt;
        }

        // Plus the PSM vault's yield, if it's sUSDS-like
        address _psmVault = _l.psmVault();
        if (_psmVault == address(0)) return _revenue;
        try ISUSDS(_psmVault).ssr() returns (uint256 _ssr) {
            uint256 _psmAssets = _l.freePsmAssets() * _WAD / 10 ** _l.psmAssetDecimals();
            _revenue += _psmAssets * (_ssr - _RAY) * _SECONDS_PER_YEAR / _RAY;
        } catch {}
    }

    /// @notice Price of a strategy's rewards in `asset`
    /// @dev The manual price if set, else the Uniswap V4 pool's spot price
    /// @param _strategy Strategy to price the rewards of
    /// @return `asset` per reward token, WAD scaled
    function price(
        address _strategy
    ) public view returns (uint256) {
        uint256 _price = manualPrices[_strategy];
        if (_price != 0) return _price;

        // currency1 per currency0, Q96
        (uint160 _sqrtPriceX96,,,) = STATE_VIEW.getSlot0(poolIds[_strategy]);
        uint256 _priceX96 = Math.mulDiv(_sqrtPriceX96, _sqrtPriceX96, 1 << 96);
        if (_priceX96 == 0) return 0;

        // Rewards are currency0 if they sort first
        return IStrategyInterface(_strategy).REWARDS_TOKEN() < IStrategyInterface(_strategy).asset()
            ? Math.mulDiv(_priceX96, _WAD, 1 << 96)
            : Math.mulDiv(_WAD, 1 << 96, _priceX96);
    }

    // ===============================================================
    // Governance functions
    // ===============================================================

    /// @notice Allow or disallow an address to set manual prices
    /// @param _keeper Address to set
    /// @param _allowed True to allow
    function setKeeper(
        address _keeper,
        bool _allowed
    ) external onlyGovernance {
        keepers[_keeper] = _allowed;
    }

    /// @notice Set the Uniswap V4 pool pricing a strategy's rewards
    /// @param _strategy Strategy to set the pool for
    /// @param _fee Pool fee in hundredths of a bip
    /// @param _tickSpacing Pool tick spacing
    /// @param _hooks Pool hooks
    function setPool(
        address _strategy,
        uint24 _fee,
        int24 _tickSpacing,
        address _hooks
    ) external onlyGovernance {
        address _rewards = IStrategyInterface(_strategy).REWARDS_TOKEN();
        address _asset = IStrategyInterface(_strategy).asset();
        (address _currency0, address _currency1) = _rewards < _asset ? (_rewards, _asset) : (_asset, _rewards);
        bytes32 _poolId = keccak256(abi.encode(_currency0, _currency1, _fee, _tickSpacing, _hooks));

        (uint160 _sqrtPriceX96,,,) = STATE_VIEW.getSlot0(_poolId);
        require(_sqrtPriceX96 != 0, "!pool");
        poolIds[_strategy] = _poolId;
    }

    // ===============================================================
    // Keeper functions
    // ===============================================================

    /// @notice Set a manual price for a strategy's rewards
    /// @dev 0 goes back to the Uniswap V4 pool
    /// @param _strategy Strategy to set the price for
    /// @param _price `asset` per reward token, WAD scaled
    function setManualPrice(
        address _strategy,
        uint256 _price
    ) external onlyKeepers {
        manualPrices[_strategy] = _price;
    }

}
