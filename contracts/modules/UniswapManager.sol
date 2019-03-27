pragma solidity ^0.5.4;
import "../wallet/BaseWallet.sol";
import "./common/BaseModule.sol";
import "./common/RelayerModule.sol";
import "./common/OnlyOwnerModule.sol";
import "../exchange/ERC20.sol";
import "../utils/SafeMath.sol";
import "../utils/SafeMath.sol";
import "../storage/GuardianStorage.sol";

interface UniswapFactory {
    function getExchange(address _token) external view returns(address);
}

contract UniswapManager is BaseModule, RelayerModule, OnlyOwnerModule {

    bytes32 constant NAME = "UniswapManager";

    using SafeMath for uint256;

    // The Uniswap factory contract
    UniswapFactory uniswap;
    // The Guardian storage 
    GuardianStorage public guardianStorage;

    /**
     * @dev Throws if the wallet is locked.
     */
    modifier onlyWhenUnlocked(BaseWallet _wallet) {
        require(!guardianStorage.isLocked(_wallet), "TT: wallet must be unlocked");
        _;
    }

    constructor(
        ModuleRegistry _registry, 
        GuardianStorage _guardianStorage, 
        address _uniswap
    ) 
        BaseModule(_registry, NAME) 
        public 
    {
        guardianStorage = GuardianStorage(_guardianStorage);
        uniswap = UniswapFactory(_uniswap);
    }
 
    /**
     * @dev Adds liquidity to a Uniswap ETH-ERC20 pair.
     * @param _wallet The target wallet
     * @param _poolToken The address of the ERC20 token of the pair.
     * @param _ethAmount The amount of ETH available.
     * @param _tokenAmount The amount of ERC20 token available.
     * @return the number of liquidity shares minted. 
     */
    function addLiquidityToUniswap(
        BaseWallet _wallet, 
        address _poolToken, 
        uint256 _ethAmount, 
        uint256 _tokenAmount
    )
        external 
        onlyOwner(_wallet)
        onlyWhenUnlocked(_wallet)
    {
        address pool = uniswap.getExchange(_poolToken);
        require(pool != address(0), "UM: The target token is not traded on Uniswap");

        uint256 ethPoolSize = address(pool).balance;
        uint256 tokenPoolSize = ERC20(_poolToken).balanceOf(pool);

        uint256 tokenInEth = getInputToOutputPrice(_tokenAmount, tokenPoolSize, ethPoolSize);
        if(_ethAmount >= tokenInEth) {
            // swap some eth for tokens
            (uint256 ethSwap, uint256 ethPool, uint256 tokenPool) = computePooledValue(ethPoolSize, tokenPoolSize, _ethAmount, _tokenAmount, tokenInEth);
            _wallet.invoke(pool, ethSwap, abi.encodeWithSignature("ethToTokenSwapInput(uint256,uint256)", 1, block.timestamp));
            _wallet.invoke(_poolToken, 0, abi.encodeWithSignature("approve(address,uint256)", pool, tokenPool));
            // add liquidity
            _wallet.invoke(pool, ethPool, abi.encodeWithSignature("addLiquidity(uint256,uint256,uint256)",1, tokenPool, block.timestamp + 1));
        }
        else {
            // swap some tokens for eth
            (uint256 tokenSwap, uint256 tokenPool, uint256 ethPool) = computePooledValue(tokenPoolSize, ethPoolSize, _tokenAmount, _ethAmount, 0);
            _wallet.invoke(_poolToken, 0, abi.encodeWithSignature("approve(address,uint256)", pool, tokenSwap + tokenPool));
            _wallet.invoke(pool, 0, abi.encodeWithSignature("tokenToEthSwapInput(uint256,uint256,uint256)", tokenSwap, 1, block.timestamp));
            // add liquidity
            _wallet.invoke(pool, ethPool - 1, abi.encodeWithSignature("addLiquidity(uint256,uint256,uint256)",1, tokenPool, block.timestamp + 1));
        }
    }

    function removeLiquidityFromUniswap(    
        BaseWallet _wallet, 
        address _poolToken, 
        uint256 _amount
    )
        external 
        onlyOwner(_wallet)
        onlyWhenUnlocked(_wallet)        
    {
        address pool = uniswap.getExchange(_poolToken);
        require(pool != address(0), "UM: The target token is not traded on Uniswap");
        _wallet.invoke(pool, 0, abi.encodeWithSignature("removeLiquidity(uint256,uint256,uint256,uint256)",_amount, 1, 1, block.timestamp + 1));
    }

    /**
     * @dev Computes the amount of tokens to swap and pool when there are more value in "major" tokens then "minor".
     * @param _majorPoolSize The size of the pool in major tokens
     * @param _minorPoolSize The size of the pool in minor tokens
     * @param _majorAmount The amount of major token provided
     * @param _minorAmount The amount of minor token provided
     * @param _minorInMajor The amount of minor token converted to major (optional)
     */
    function computePooledValue(
        uint256 _majorPoolSize,
        uint256 _minorPoolSize, 
        uint256 _majorAmount,
        uint256 _minorAmount, 
        uint256 _minorInMajor
    ) 
        internal 
        view 
        returns(uint256 _majorSwap, uint256 _majorPool, uint256 _minorPool) 
    {
        if(_minorInMajor == 0) {
            _minorInMajor = getInputToOutputPrice(_minorAmount, _minorPoolSize, _majorPoolSize); 
        }
        _majorSwap = (_majorAmount - _minorInMajor) * 1003 / 2000;
        uint256 minorSwap = getInputToOutputPrice(_majorSwap, _majorPoolSize, _minorPoolSize);
        _majorPool = _majorAmount - _majorSwap;
        _minorPool = _majorPool.mul(_minorPoolSize.sub(minorSwap)).div(_majorPoolSize.add(_majorSwap)) + 1;
        uint256 minorPoolMax = _minorAmount.add(minorSwap);
        if(_minorPool > minorPoolMax) {
            _minorPool = minorPoolMax;
            _majorPool = _minorPool.mul(_majorPoolSize.add(_majorSwap)).div(_minorPoolSize.sub(minorSwap)) + 1;
        }
        assert(_majorAmount >= _majorPool + _majorSwap);
    }

    /**
     * @dev Computes the amount of output tokens that can be obtained by swapping the provided amoutn of input.
     * @param _inputAmount The amount of input token.
     * @param _inputPoolSize The size of the input pool.
     * @param _outputPoolSize The size of the output pool.
     */
    function getInputToOutputPrice(uint256 _inputAmount, uint256 _inputPoolSize, uint256 _outputPoolSize) internal view returns(uint256) {
        if(_inputAmount == 0) {
            return 0;
        }
        uint256 inputWithFee = _inputAmount.mul(997);
        uint256 numerator = inputWithFee.mul(_outputPoolSize);
        uint256 denominator = _inputPoolSize.mul(1000) + inputWithFee;
        return numerator.div(denominator);
    }
}