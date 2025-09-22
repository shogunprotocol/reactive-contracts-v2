// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../lib/reactive-lib/src/abstract-base/AbstractCallback.sol";

/**
 * @title MockEmergencySwap
 * @dev Contrato mock que simula swaps para testing del sistema reactivo
 *      Hereda de AbstractCallback para recibir callbacks del reactive network
 */
contract MockEmergencySwap is ReentrancyGuard, AbstractCallback {
    using SafeERC20 for IERC20;

    // Tokens en Sepolia (mismos que tu sistema)
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant WETH = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    // Mock exchange rate: 1 USDC = 0.00000000 WBTC (simplified)
    uint256 public constant MOCK_RATE = 3000000000; // 0.00000000 WBTC por USDC

    address public owner;

    // Events
    event MockSwapExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address indexed recipient
    );

    event EmergencySwapTriggered(
        uint256 amountIn,
        uint256 amountOut,
        address recipient
    );

    event FundsDeposited(address token, uint256 amount);

    constructor(
        address _callback_sender
    ) payable AbstractCallback(_callback_sender) {
        owner = msg.sender;
    }

    event CallbackReceived(
        address indexed origin,
        address indexed sender,
        address indexed reactive_sender
    );

    /**
     * @dev Mock swap USDC -> WETH (NO usa Uniswap real)
     * @param amountIn Cantidad de USDC a swapear
     * @param amountOutMin Cantidad mínima de WETH a recibir (ignorado en mock)
     * @param recipient Dirección que recibirá el WETH
     */
    function swapUSDCToWETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address recipient
    ) external nonReentrant returns (uint256 amountOut) {
        require(amountIn > 0, "Amount must be > 0");
        require(recipient != address(0), "Invalid recipient");

        // 1. Transferir USDC del caller a este contrato
        IERC20(USDC).safeTransferFrom(msg.sender, address(this), amountIn);

        // 2. Calcular WETH simulado usando mock rate
        amountOut = (amountIn * MOCK_RATE) / 1e6; // USDC has 6 decimals

        // 3. Verificar que tenemos suficiente WETH en el contrato
        uint256 contractWETH = IERC20(WETH).balanceOf(address(this));
        require(
            contractWETH >= amountOut,
            "Insufficient WETH in contract - add liquidity"
        );

        // 4. Enviar WETH al recipient
        IERC20(WETH).safeTransfer(recipient, amountOut);

        emit MockSwapExecuted(USDC, WETH, amountIn, amountOut, recipient);
        return amountOut;
    }

    /**
     * @dev Internal helper para ejecutar swaps
     */
    function _executeEmergencySwap(
        uint256 amount,
        address recipient,
        uint256 minAmount
    ) internal returns (uint256 amountOut) {
        require(amount > 0, "Amount must be > 0");
        require(recipient != address(0), "Invalid recipient");

        // Calcular WETH usando mock rate
        amountOut = (amount * MOCK_RATE) / 1e8;

        // Verificar que tenemos suficiente WETH
        uint256 contractWETH = IERC20(WETH).balanceOf(address(this));
        require(contractWETH >= amountOut, "Insufficient WETH in contract");

        // Transferir WETH al recipient
        IERC20(WETH).safeTransfer(recipient, amountOut);

        return amountOut;
    }

    /**
     * @dev Función de emergency swap (para llamadas directas)
     * @param amount Cantidad a swapear
     * @param recipient Dirección destino
     * @param minAmount Cantidad mínima esperada (ignorado en mock)
     */
    function emergencySwap(
        uint256 amount,
        address recipient,
        uint256 minAmount
    ) external authorizedSenderOnly nonReentrant returns (uint256 amountOut) {
        require(amount > 0, "Amount must be > 0");
        require(recipient != address(0), "Invalid recipient");

        // Get USDC from owner via transferFrom (reactive pattern)
        uint256 ownerBalance = IERC20(USDC).balanceOf(owner);
        uint256 transferAmount = amount > ownerBalance ? ownerBalance : amount;

        if (transferAmount > 0) {
            IERC20(USDC).transferFrom(owner, address(this), transferAmount);

            // Execute emergency swap: USDC -> WETH
            amountOut = _executeEmergencySwap(
                transferAmount,
                recipient,
                minAmount
            );
            emit EmergencySwapTriggered(transferAmount, amountOut, recipient);
        }

        return amountOut;
    }

    /**
     * @dev Depositar USDC en este contrato
     */
    function depositUSDC(uint256 amount) external {
        require(amount > 0, "Amount must be > 0");
        IERC20(USDC).safeTransferFrom(msg.sender, address(this), amount);
        emit FundsDeposited(USDC, amount);
    }

    /**
     * @dev Depositar WETH en este contrato (para hacer swaps)
     */
    function depositWETH(uint256 amount) external {
        require(amount > 0, "Amount must be > 0");
        IERC20(WETH).safeTransferFrom(msg.sender, address(this), amount);
        emit FundsDeposited(WETH, amount);
    }

    /**
     * @dev Enviar ETH y convertir a WETH automáticamente
     */
    function depositETHAsWETH() external payable {
        require(msg.value > 0, "Must send ETH");

        // En un contrato real, aquí convertiríamos ETH a WETH
        // Para mock, solo registramos que recibimos ETH
        emit FundsDeposited(WETH, msg.value);
    }

    /**
     * @dev Ver balances de tokens en este contrato
     */
    function getBalances()
        external
        view
        returns (uint256 usdcBalance, uint256 wethBalance)
    {
        usdcBalance = IERC20(USDC).balanceOf(address(this));
        wethBalance = IERC20(WETH).balanceOf(address(this));
    }

    /**
     * @dev Obtener cotización mock
     */
    function getQuote(
        uint256 amountIn
    ) external pure returns (uint256 amountOut) {
        return (amountIn * MOCK_RATE) / 1e6;
    }

    /**
     * @dev Retirar tokens (solo owner)
     */
    function withdraw(address token, uint256 amount) external {
        require(msg.sender == owner, "Only owner");
        IERC20(token).safeTransfer(owner, amount);
    }

    /**
     * @dev Retirar ETH (solo owner)
     */
    function withdrawETH() external {
        require(msg.sender == owner, "Only owner");
        payable(owner).transfer(address(this).balance);
    }

    /**
     * @dev Función para aprobar tokens fácilmente
     */
    function approveTokens() external {
        IERC20(USDC).approve(address(this), type(uint256).max);
        IERC20(WETH).approve(address(this), type(uint256).max);
    }

    receive() external payable override {
        emit FundsDeposited(address(0), msg.value);
    }
}
