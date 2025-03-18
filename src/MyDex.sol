// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "../lib/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "../lib/v2-periphery/contracts/interfaces/IWETH.sol";
import "./interfaces/IDex.sol";

contract MyDex is IDex {
    IUniswapV2Factory public immutable factory;
    address public immutable WETH;
    uint256 private constant FEE_NUMERATOR = 997;
    uint256 private constant FEE_DENOMINATOR = 1000;

    constructor(address _factory, address _weth) {
        require(_factory != address(0), "Invalid factory");
        require(_weth != address(0), "Invalid WETH");
        factory = IUniswapV2Factory(_factory);
        WETH = _weth;
    }

    function getPairAddress(address tokenA, address tokenB) public view returns (address pair) {
        return factory.getPair(tokenA, tokenB);
    }

    function sellETH(address buyToken, uint256 minBuyAmount) external payable {
        require(msg.value > 0, "Must send ETH to sell");
        require(buyToken != address(0) && buyToken != WETH, "Invalid token");
        require(minBuyAmount > 0, "Invalid min amount");
        
        // 获取交易对地址
        address pair = getPairAddress(buyToken, WETH);
        require(pair != address(0), "Pair does not exist");
        
        // 将 ETH 转换为 WETH
        IWETH(WETH).deposit{value: msg.value}();
        
        // 获取储备量并计算输出金额
        (uint256 amountOut, address token0) = _getAmountOut(msg.value, WETH, buyToken, pair);
        require(amountOut >= minBuyAmount, "Insufficient output amount");
        
        // 给交易对批准 WETH
        IWETH(WETH).approve(pair, msg.value);
        
        // 向交易对转移 WETH
        IWETH(WETH).transfer(pair, msg.value);
        
        // 执行交换
        IUniswapV2Pair(pair).swap(
            buyToken == token0 ? amountOut : 0, 
            buyToken == token0 ? 0 : amountOut, 
            msg.sender, 
            new bytes(0)
        );
    }

    function buyETH(address sellToken, uint256 sellAmount, uint256 minBuyAmount) external override {
        require(sellToken != address(0) && sellToken != WETH, "Invalid token");
        require(sellAmount > 0, "Amount must be > 0");
        require(minBuyAmount > 0, "Invalid min amount");

        // 获取交易对地址
        address pair = getPairAddress(sellToken, WETH);
        require(pair != address(0), "Pair not exists");

        // 从用户转移代币
        IERC20(sellToken).transferFrom(msg.sender, address(this), sellAmount);

        // 获取储备量并计算输出金额
        (uint256 amountOut, address token0) = _getAmountOut(sellAmount, sellToken, WETH, pair);
        require(amountOut >= minBuyAmount, "Insufficient output amount");

        // 给交易对批准代币
        IERC20(sellToken).approve(pair, sellAmount);
        
        // 向交易对转移代币
        IERC20(sellToken).transfer(pair, sellAmount);

        // 执行交换
        IUniswapV2Pair(pair).swap(
            WETH == token0 ? amountOut : 0, 
            WETH == token0 ? 0 : amountOut, 
            address(this), 
            new bytes(0)
        );
        
        // 将 WETH 转换回 ETH 并发送给用户
        IWETH(WETH).withdraw(amountOut);
        (bool success, ) = msg.sender.call{value: amountOut}("");
        require(success, "ETH transfer failed");
    }

    // 内部函数：计算输出金额
    function _getAmountOut(
        uint256 amountIn,
        address tokenIn,
        address tokenOut,
        address pair
    ) internal view returns (uint256 amountOut, address token0) {
        // 获取储备量
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        require(reserve0 > 0 && reserve1 > 0, "Insufficient liquidity");
        
        // 确保 token0 和 token1 的顺序正确
        (token0,) = sortTokens(tokenIn, tokenOut);
        (uint reserveIn, uint reserveOut) = tokenIn == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
        
        // 计算输出金额 (使用 Uniswap 的公式)
        uint amountInWithFee = amountIn * FEE_NUMERATOR;
        uint numerator = amountInWithFee * reserveOut;
        uint denominator = (reserveIn * FEE_DENOMINATOR) + amountInWithFee;
        amountOut = numerator / denominator;
    }

    // 辅助函数: 按顺序排列代币地址
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, "Same token");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "Zero address");
    }

    // 接收 ETH
    receive() external payable {}
}