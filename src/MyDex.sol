// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract MyDex {
    IUniswapV2Factory public immutable factory;
    IUniswapV2Router02 public immutable router;
    address public immutable WETH;

    constructor(address _factory, address _router) {
        factory = IUniswapV2Factory(_factory);
        router = IUniswapV2Router02(_router);
        WETH = router.WETH();
    }

    // Create a new liquidity pool for a token with ETH
    function createPair(address token) external returns (address) {
        return factory.createPair(token, WETH);
    }

    // Add liquidity to a token-ETH pair
    function addLiquidity(
        address token,
        uint amountToken,
        uint amountETH,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountTokenOut, uint amountETHOut, uint liquidity) {
        IERC20(token).transferFrom(msg.sender, address(this), amountToken);
        IERC20(token).approve(address(router), amountToken);

        require(msg.value >= amountETH, "Insufficient ETH sent");

        (amountTokenOut, amountETHOut, liquidity) = router.addLiquidityETH{value: amountETH}(
            token,
            amountToken,
            amountTokenMin,
            amountETHMin,
            to,
            deadline
        );

        // Refund excess ETH if any
        if (msg.value > amountETH) {
            (bool success, ) = msg.sender.call{value: msg.value - amountETH}("");
            require(success, "ETH refund failed");
        }

        // Refund excess tokens if any
        if (amountToken > amountTokenOut) {
            IERC20(token).transfer(msg.sender, amountToken - amountTokenOut);
        }

        return (amountTokenOut, amountETHOut, liquidity);
    }

    // Remove liquidity from a token-ETH pair
    function removeLiquidity(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountETH) {
        address pair = factory.getPair(token, WETH);
        IERC20(pair).transferFrom(msg.sender, address(this), liquidity);
        IERC20(pair).approve(address(router), liquidity);

        return router.removeLiquidityETH(
            token,
            liquidity,
            amountTokenMin,
            amountETHMin,
            to,
            deadline
        );
    }

    // Swap tokens for ETH
    function swapTokensForETH(
        address token,
        uint amountIn,
        uint amountOutMin,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts) {
        IERC20(token).transferFrom(msg.sender, address(this), amountIn);
        IERC20(token).approve(address(router), amountIn);

        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = WETH;

        return router.swapExactTokensForETH(
            amountIn,
            amountOutMin,
            path,
            to,
            deadline
        );
    }

    // Swap ETH for tokens
    function swapETHForTokens(
        address token,
        uint amountOutMin,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts) {
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = token;

        return router.swapExactETHForTokens{value: msg.value}(
            amountOutMin,
            path,
            to,
            deadline
        );
    }

    // Get the amount of tokens that would be received for a given amount of ETH
    function getETHToTokenAmount(address token, uint amountETH) external view returns (uint) {
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = token;

        uint[] memory amounts = router.getAmountsOut(amountETH, path);
        return amounts[1];
    }

    // Get the amount of ETH that would be received for a given amount of tokens
    function getTokenToETHAmount(address token, uint amountToken) external view returns (uint) {
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = WETH;

        uint[] memory amounts = router.getAmountsOut(amountToken, path);
        return amounts[1];
    }

    // Fallback function to receive ETH
    receive() external payable {}
} 