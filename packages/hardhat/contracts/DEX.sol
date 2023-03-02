// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DEX Template
 * @author stevepham.eth and m00npapi.eth
 * @notice Empty DEX.sol that just outlines what features could be part of the challenge (up to you!)
 * @dev We want to create an automatic market where our contract will hold reserves of both ETH and 🎈 Balloons. These reserves will provide liquidity that allows anyone to swap between the assets.
 * NOTE: functions outlined here are what work with the front end of this branch/repo. Also return variable names that may need to be specified exactly may be referenced (if you are confused, see solutions folder in this repo and/or cross reference with front-end code).
 */
contract DEX is Ownable {
    /* ========== GLOBAL VARIABLES ========== */

    using SafeMath for uint256; //outlines use of SafeMath for uint256 variables
    IERC20 token; //instantiates the imported contract
    uint256 public totalLiquidity;
    mapping(address => uint256) public liquidity;

    /* ========== EVENTS ========== */

    /**
     * @notice Emitted when ethToToken() swap transacted
     */
    event EthToTokenSwap(address, string, uint256, uint256);

    /**
     * @notice Emitted when tokenToEth() swap transacted
     */
    event TokenToEthSwap(address, string, uint256, uint256);

    /**
     * @notice Emitted when liquidity provided to DEX and mints LPTs.
     */
    event LiquidityProvided(address, uint256, uint256, uint256);

    /**
     * @notice Emitted when liquidity removed from DEX and decreases LPT count within DEX.
     */
    event LiquidityRemoved(address, uint256, uint256, uint256);

    /* ========== CONSTRUCTOR ========== */

    constructor(address token_addr) {
        token = IERC20(token_addr); //specifies the token address that will hook into the interface and be used through the variable 'token'
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @notice initializes amount of tokens that will be transferred to the DEX itself from the erc20 contract mintee (and only them based on how Balloons.sol is written). Loads contract up with both ETH and Balloons.
     * @param tokens amount to be transferred to DEX
     * @return totalLiquidity is the number of LPTs minting as a result of deposits made to DEX contract
     * NOTE: since ratio is 1:1, this is fine to initialize the totalLiquidity (wrt to balloons) as equal to eth balance of contract.
     */
    function init(uint256 tokens) public payable returns (uint256) {
        require(totalLiquidity == 0, "Already initialised");
        totalLiquidity = msg.value;
        liquidity[msg.sender] = totalLiquidity;
        require(tokens == msg.value, "Didn't initialise with 1:1 ratio");
        require(
            token.transferFrom(msg.sender, address(this), tokens),
            "Transfer failed"
        );
        return totalLiquidity;
    }

    // ToDo: create a withdraw() function that lets the owner withdraw ETH
    function recoverEth() public onlyOwner {
        require(address(this).balance > 0, "No balance");
        (bool sent, ) = msg.sender.call{value: address(this).balance}("");
        require(sent, "Transaction failed to send");
    }

    /**
     * @notice returns yOutput, or yDelta for xInput (or xDelta)
     * @dev Follow along with the [original tutorial](https://medium.com/@austin_48503/%EF%B8%8F-minimum-viable-exchange-d84f30bd0c90) Price section for an understanding of the DEX's pricing model and for a price function to add to your contract. You may need to update the Solidity syntax (e.g. use + instead of .add, * instead of .mul, etc). Deploy when you are done.
     */
    function price(
        uint256 xInput,
        uint256 xReserves,
        uint256 yReserves
    ) public pure returns (uint256 yOutput) {
        return
            ((xInput * 997) * yReserves) / (xReserves * 1000 + (xInput * 997));
        // yOutput = yReserves - (xReserves * yReserves) / (xReserves + xInput)
        // yOutput = yReserves * xInput / (xReserves + xInput)
    }

    /**
     * @notice returns liquidity for a user. Note this is not needed typically due to the `liquidity()` mapping variable being public and having a getter as a result. This is left though as it is used within the front end code (App.jsx).
     * if you are using a mapping liquidity, then you can use `return liquidity[lp]` to get the liquidity for a user.
     *
     */
    function getLiquidity(address lp) public view returns (uint256) {
        return liquidity[lp];
    }

    /**
     * @notice sends Ether to DEX in exchange for $BAL
     */
    function ethToToken() public payable returns (uint256 tokenOutput) {
        require(msg.value > 0);
        uint256 ethReserve = address(this).balance - msg.value;
        uint256 ethInput = msg.value;
        tokenOutput = this.price(
            ethInput,
            ethReserve,
            token.balanceOf(address(this))
        );
        require(token.transfer(msg.sender, tokenOutput));
        emit EthToTokenSwap(
            msg.sender,
            "Eth to Balloons",
            msg.value,
            tokenOutput
        );
    }

    /**
     * @notice sends $BAL tokens to DEX in exchange for Ether
     */
    function tokenToEth(uint256 tokenInput) public returns (uint256 ethOutput) {
        require(tokenInput > 0);
        require(token.transferFrom(msg.sender, address(this), tokenInput));
        ethOutput = this.price(
            tokenInput,
            token.balanceOf(address(this)),
            address(this).balance
        );
        (bool sent, ) = msg.sender.call{value: ethOutput}("");
        require(sent, "Transaction failed to send");
        emit TokenToEthSwap(
            msg.sender,
            "Balloons to ETH",
            ethOutput,
            tokenInput
        );
    }

    /**
     * @notice allows deposits of $BAL and $ETH to liquidity pool
     * NOTE: parameter is the msg.value sent with this function call. That amount is used to determine the amount of $BAL needed as well and taken from the depositor.
     * NOTE: user has to make sure to give DEX approval to spend their tokens on their behalf by calling approve function prior to this function call.
     * NOTE: Equal parts of both assets will be removed from the user's wallet with respect to the price outlined by the AMM.
     */
    function deposit() public payable returns (uint256 tokensDeposited) {
        require(msg.value > 0);
        uint256 ethIn = msg.value;
        uint256 ethReserve = address(this).balance - msg.value;
        uint256 tokenReserve = token.balanceOf(address(this));
        tokensDeposited = ((ethIn * tokenReserve) / ethReserve) + 1;
        require(token.transferFrom(msg.sender, address(this), tokensDeposited));
        uint256 deltaLiquidity = (totalLiquidity * ethIn) / ethReserve;
        liquidity[msg.sender] += deltaLiquidity;
        totalLiquidity += deltaLiquidity;
        emit LiquidityProvided(
            msg.sender,
            deltaLiquidity,
            msg.value,
            tokensDeposited
        );
    }

    // function deposit() public payable returns (uint256 tokensDeposited) {
    //     require(msg.value > 0, "Must send value when depositing");
    //     uint256 ethReserve = address(this).balance.sub(msg.value);
    //     uint256 tokenReserve = token.balanceOf(address(this));
    //     uint256 tokenDeposit;

    //     tokenDeposit = (msg.value.mul(tokenReserve) / ethReserve).add(1);
    //     // 💡 Discussion on adding 1 wei at end of calculation   ^
    //     // -> https://t.me/c/1655715571/106

    //     uint256 liquidityMinted = msg.value.mul(totalLiquidity) / ethReserve;
    //     liquidity[msg.sender] = liquidity[msg.sender].add(liquidityMinted);
    //     totalLiquidity = totalLiquidity.add(liquidityMinted);

    //     require(token.transferFrom(msg.sender, address(this), tokenDeposit));
    //     // emit LiquidityProvided(msg.sender, liquidityMinted, msg.value, tokenDeposit);
    //     return tokenDeposit;
    // }

    /**
     * @notice allows withdrawal of $BAL and $ETH from liquidity pool
     * NOTE: with this current code, the msg caller could end up getting very little back if the liquidity is super low in the pool. I guess they could see that with the UI.
     */
    function withdraw(
        uint256 liquidityAmount
    ) public returns (uint256 ethAmount, uint256 tokenAmount) {
        require(liquidityAmount > 0);
        require(liquidityAmount <= liquidity[msg.sender]);
        uint256 ethReserve = address(this).balance;
        uint256 tokenReserve = token.balanceOf(address(this));
        tokenAmount = (tokenReserve * liquidityAmount) / totalLiquidity;
        ethAmount = (ethReserve * liquidityAmount) / totalLiquidity;

        liquidity[msg.sender] -= liquidityAmount;
        totalLiquidity -= liquidityAmount;

        require(token.transfer(msg.sender, tokenAmount));
        (bool sent, ) = msg.sender.call{value: ethAmount}("");
        require(sent, "Transaction failed to send");
        emit LiquidityRemoved(
            msg.sender,
            liquidityAmount,
            ethAmount,
            tokenAmount
        );
    }
   
}