// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/IPancakeRouter02.sol";
import "./interfaces/IPancakeFactory.sol";
import "./BEP20.sol";

/// @author The Development Team
/// @title Token
contract ConquerUranus is BEP20("ConquerUranus", "ANVS", 18) {

    using SafeMath for uint256;
    using Address for address;

    mapping(address => uint256) private _rOwned;
    mapping(address => uint256) private _tOwned;
    mapping(address => mapping(address => uint256)) private _allowances;

    mapping(address => bool) private _isExcludedFromReward;
    address[] private _excludedFromReward;

    uint256 private constant MAX = ~uint256(0);
    uint256 private _tTotal = 2543164 * 10**6 * 10**18;
    uint256 private _rTotal = (MAX - (MAX % _tTotal));
    uint256 private _tFeeTotal;

    /// Control the amount on transfers to avoid dump price
    uint256 public _maxTxAmount = (_tTotal * 5).div(1000);
    uint256 private numTokensSellToAddToLiquidity = (_tTotal * 5).div(1000);

    /// Fee state variables section
    uint256 public _holderFee;
    uint256 public _liquidityFee;
    uint256 public _vaultFee;

    uint256 public totalSendedToTheVoid;
    uint256 public totalLiquidity;

    IPancakeRouter02 public immutable pancakeRouter;
    address public immutable pancakePair;

    address public blackHoleVaultAddress;
    address public spaceWasteVaultAddress;
    address public devAddress;

    bool inSwapAndLiquify;
    bool public swapAndLiquifyEnabled;

    /// Event section
    event MinTokensBeforeSwapUpdated(uint256 minTokensBeforeSwap);
    event SwapAndLiquifyEnabledUpdated(bool enabled);
    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );
    event Burn(address indexed burner, uint256 amount);

    /// Modifiers section

    /// Modifier that uses a mutex pattern for swaps
    modifier lockTheSwap {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

    /// Modifier that restricts the users who can send to the void
    modifier sendersToTheVoid {
        require(
            _msgSender() == owner() ||
            _msgSender() == devAddress ||
            _msgSender() == blackHoleVaultAddress
        );
        _;
    }

    /// Modifier that restricts a function only for vault address
    modifier onlyVault {
        require(_msgSender() == blackHoleVaultAddress);
        _;
    }

    constructor (
        address blackHoleVaultAddress_,
        address devAddress_,
        address routerAddress_,
        address spaceWasteVaultAddress_
    )
    {

        // Declaration of addresses
        blackHoleVaultAddress = blackHoleVaultAddress_;
        devAddress = devAddress_;
        spaceWasteVaultAddress = spaceWasteVaultAddress_;

        swapAndLiquifyEnabled = true;

        _rOwned[_msgSender()] = _rTotal;

        IPancakeRouter02 _pancakeRouter = IPancakeRouter02(routerAddress_);
        // Creation of pancake pair for the token
        pancakePair = IPancakeFactory(_pancakeRouter.factory())
        .createPair(address(this), _pancakeRouter.WETH());

        // set the rest of the contract variables
        pancakeRouter = _pancakeRouter;

        // Excluding main accounts from rewards
        excludeFromReward(address(this));
        excludeFromReward(owner());
        excludeFromReward(blackHoleVaultAddress);
        excludeFromReward(devAddress);
        excludeFromReward(spaceWasteVaultAddress);

        emit Transfer(address(0), _msgSender(), _tTotal);
    }

    //to recieve BNB from pancakeRouter when swaping
    receive() external payable {}

    /// This function include and account into reward system. Only an Owner can include.
    /// @param account The address of the account to include
    function includeInReward(address account) external onlyOwner {
        require(_isExcludedFromReward[account], "Account is already excluded");
        for (uint256 i = 0; i < _excludedFromReward.length; i++) {
            if (_excludedFromReward[i] == account) {
                _excludedFromReward[i] = _excludedFromReward[_excludedFromReward.length - 1];
                _tOwned[account] = 0;
                _isExcludedFromReward[account] = false;
                _excludedFromReward.pop();
                break;
            }
        }
    }

    /// This function permits change the holder fee percent
    /// Only owner can change the fee
    /// @param holderFee is the new fee for holders
    function setHoldersFee(uint256 holderFee, uint256 liquidityFee, uint256 vaultFee) external onlyOwner {
        _holderFee = holderFee;
        _liquidityFee = liquidityFee;
        _vaultFee = vaultFee;
    }

    /// This function sets the max percent for transfers
    /// @param maxTxPercent is the new percentaje
    function setMaxTxPercent(uint256 maxTxPercent) external onlyOwner {
        _maxTxAmount = _tTotal.mul(maxTxPercent).div(
            10**2
        );
    }

    /// This function enable or disable the swap and liquify function
    /// @param _enabled is the boolean value to set
    function setSwapAndLiquifyEnabled(bool _enabled) public onlyOwner {
        swapAndLiquifyEnabled = _enabled;
        emit SwapAndLiquifyEnabledUpdated(_enabled);
    }

    /// This is the public function to send the half of tokens in vault to the black hole
    /// and the other half to the dev wallet
    /// @return a boolean value
    function sendToTheVoidDevAndSpaceWasteWallet() public onlyVault returns (bool) {
        // Take tokens from vault
        uint256 amountToBlackHole = _tOwned[blackHoleVaultAddress].div(2);
        uint256 amountToDistribute = _tOwned[blackHoleVaultAddress].sub(amountToBlackHole);
        uint256 amountToDev = amountToDistribute.div(2);
        uint256 amountToSpaceWasteVault = amountToDistribute.sub(amountToDev);
        _tOwned[blackHoleVaultAddress] = 0;

        // We distribute to black hole and developers wallet
        // Sending to black hole
        _sendToTheVoid(amountToBlackHole);

        // Sending to devs wallet
        _tOwned[devAddress] = _tOwned[devAddress].add(amountToDev);
        _tOwned[spaceWasteVaultAddress] = _tOwned[spaceWasteVaultAddress].add(amountToSpaceWasteVault);
        emit Transfer(blackHoleVaultAddress, devAddress, amountToDev);
        emit Transfer(blackHoleVaultAddress, spaceWasteVaultAddress, amountToSpaceWasteVault);
        return true;
    }

    /// This is the public function to send tokens to the black hole
    /// @dev Only can burn Owner, Vault and Dev
    /// @param amount the quantity to burn
    /// @return a boolean value
    function sendToTheVoid(uint256 amount) public sendersToTheVoid returns (bool) {
        _sendToTheVoid(amount);
        return true;
    }

    /// This function deliver an amount to the totalFees
    /// @param tAmount is the quantity of token to deliver
    function deliver(uint256 tAmount) public {
        address sender = _msgSender();
        require(!_isExcludedFromReward[sender], "Excluded addresses cannot call this function");
        (uint256 rAmount,,,,,,) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rTotal = _rTotal.sub(rAmount);
        _tFeeTotal = _tFeeTotal.add(tAmount);
    }

    /// This function exclude and account from reward, in case of the account have some reflection
    /// pass it to tokens. Only an Owner can include.
    /// @param account The address of the account to exclude
    function excludeFromReward(address account) public onlyOwner {
        require(!_isExcludedFromReward[account], "Account is already excluded");
        if(_rOwned[account] > 0) {
            _tOwned[account] = tokenFromReflection(_rOwned[account]);
        }
        _isExcludedFromReward[account] = true;
        _excludedFromReward.push(account);
    }

    /// This function calculates the conversion from normal token to reflection
    /// @param tAmount the quantity of token to convert
    /// @param deductTransferFee boolean that indicates if the conversion deduct fees in calculus or not
    /// @return the value in reflection
    function reflectionFromToken(uint256 tAmount, bool deductTransferFee) public view returns(uint256) {
        require(tAmount <= _tTotal, "Amount must be less than supply");
        if (!deductTransferFee) {
            (uint256 rAmount,,,,,,) = _getValues(tAmount);
            return rAmount;
        } else {
            (,uint256 rTransferAmount,,,,,) = _getValues(tAmount);
            return rTransferAmount;
        }
    }

    /// This function calculates the conversion from reflection to normal token
    /// @param rAmount the quantity of reflection to convert in token
    /// @return the value in token
    function tokenFromReflection(uint256 rAmount) public view returns(uint256) {
        require(rAmount <= _rTotal, "Amount must be less than total reflections");
        uint256 currentRate =  _getRate();
        return rAmount.div(currentRate);
    }

    /// This function returns the total supply of tokens
    function totalSupply() public view override  returns (uint256) {
        return _tTotal;
    }

    /// This functions shows the balance of an account
    /// @param account the account to get the balance
    /// @return an unsigned intger with the balance
    function balanceOf(address account) public view override returns (uint256) {
        if (_isExcludedFromReward[account]) return _tOwned[account];
        return tokenFromReflection(_rOwned[account]);
    }

    /// This function returns a boolean value depending on whether the account is
    /// excluded from rewards.
    /// @param account is the account to check if is excluded from reward
    /// @return boolean value with the status
    function isExcludedFromReward(address account) public view returns (bool) {
        return _isExcludedFromReward[account];
    }

    /// This function gets a list of excluded accounts from reward.
    /// @return an array with the list of excluded accounts
    function getExcludedFromReward() public view returns (address[] memory) {
        return _excludedFromReward;
    }

    /// This functions return the total fees
    /// @return an unsigned integer with the total fees
    function totalFees() public view returns (uint256) {
        return _tFeeTotal;
    }

    /// This function burns an amount defined by param
    /// @param amount the amount that will be burn
    function _sendToTheVoid(uint256 amount) internal {
        require(amount <= _tTotal, "Amount must be less than total");
        // Substract token to burn from sender account
        if(_tOwned[_msgSender()] > 0 && amount <= _tOwned[_msgSender()]){
            _tOwned[_msgSender()] = _tOwned[_msgSender()].sub(amount, "Amount to burn exceeds token owned");
        }
        // Only if account have reflection, but its not probably because dev, vault and owner are excluded from
        // reward
        uint256 ratedQuantity = amount.mul(_getRate());
        if(_rOwned[_msgSender()] > 0 && ratedQuantity <= _rOwned[_msgSender()]){
            _rOwned[_msgSender()] = _rOwned[_msgSender()].sub(ratedQuantity, "Amount to burn exceeds reflected token owned");
        }
        _tOwned[address(1)] = _tOwned[address(1)].add(amount);
        _rOwned[address(1)] = _rOwned[address(1)].add(amount.mul(_getRate()));
        totalSendedToTheVoid = totalSendedToTheVoid.add((amount));
        emit Transfer(_msgSender(), address(1), amount);
    }

    ///This function is responsible for transfering tokens, is modified from BEP20
    /// and different functionalities have been added.
    /// @param from sender of the transfer
    /// @param to recipient of the transfer
    /// @param amount quantity of tokens to transfer
    function _transfer(address from, address to, uint256 amount) internal virtual override{
        require(from != address(0), "BEP20: transfer from the zero address");
        require(to != address(0), "BEP20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        if(from != owner() && to != owner())
            require(amount <= _maxTxAmount, "Transfer amount exceeds the maxTxAmount.");

        uint256 contractTokenBalance = balanceOf(address(this));

        if(contractTokenBalance >= _maxTxAmount) {
            contractTokenBalance = _maxTxAmount;
        }

        bool overMinTokenBalance = contractTokenBalance >= numTokensSellToAddToLiquidity;
        /// Cases of condition:
        /// 1. The token balance of this contract is over the min number of
        /// tokens that we need to initiate a swap + liquidity lock (overMinTokenBalance checks it)
        /// 2. Avoid that  don't get caught in a circular liquidity event using a mutex pattern with the modifier lockTheSwap.
        /// variable inSwapAndLiquify controls it
        /// 3. Avoid swap & liquify if sender is uniswap pair with from != pancakePair.
        /// 4. swapAndLiquifyEnable, must be enabled :)
        if (
            overMinTokenBalance &&
            !inSwapAndLiquify &&
            from != pancakePair &&
            swapAndLiquifyEnabled
        ) {
            contractTokenBalance = numTokensSellToAddToLiquidity;
            //add liquidity
            swapAndLiquify(contractTokenBalance);
        }

        // Transfer amount, it will take tax, burn, liquidity fee
        _tokenTransfer(from,to,amount);
    }

    /// This function adds fee value to the total fee counter
    /// @param rFee is the value to substract from rTotal
    /// @param tFee is the value to add to tFeeTotal
    function _reflectFee(uint256 rFee, uint256 tFee) private {
        _rTotal = _rTotal.sub(rFee);
        _tFeeTotal = _tFeeTotal.add(tFee);
    }

    /// This function sends token from an excluded from reward sender to excluded from reward recipient
    /// @param sender is the account that sends tokens
    /// @param recipient is the account that will receive tokens
    /// @param tAmount is the quantity to send
    function _transferBothExcluded(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, uint256 tLiquidity, uint256 tVault) = _getValues(tAmount);
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _takeLiquidity(tLiquidity);
        _takeVault(tVault);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    /// This function is in charge of dividing the balance sheets in two
    /// and making repurchases and liquidity additions.
    /// @param contractTokenBalance only tokenBalance
    function swapAndLiquify(uint256 contractTokenBalance) private lockTheSwap {
        // This part of code splits the contract balance into halves
        uint256 half = contractTokenBalance.div(2);
        uint256 otherHalf = contractTokenBalance.sub(half);

        // capture the contract's current ETH balance.
        // this is so that we can capture exactly the amount of ETH that the
        // swap creates, and not make the liquidity event include any ETH that
        // has been manually sent to the contract
        uint256 initialBalance = address(this).balance;

        // Swap tokens of the contract for ETH
        swapTokensForETH(half); //

        // The balance of ETH to swap
        uint256 newBalance = address(this).balance.sub(initialBalance);

        // Add liquidity to pancake
        addLiquidity(otherHalf, newBalance);

        emit SwapAndLiquify(half, newBalance, otherHalf);
    }

    /// This function is in charge of taking a part of the tokens to buy BNB that will later
    /// be added to the pair together with another amount of tokens.
    /// @param tokenAmount is the quantity of tokens to change for BNB
    function swapTokensForETH(uint256 tokenAmount) private {
        // Generate the Pancake swap pair path of Token -> BNB
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = pancakeRouter.WETH();

        /// Gives the approve to router for taking tokens
        _approve(address(this), address(pancakeRouter), tokenAmount);

        /// Make the swap to get BNB
        pancakeRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of BNB
            path,
            address(this),
            block.timestamp
        );
    }

    /// This functions adds liquidity to pair
    /// @param tokenAmount quantity of tokens to add
    /// @param ethAmount quantity of BNB to add
    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(pancakeRouter), tokenAmount);

        // add the liquidity
        pancakeRouter.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            owner(),
            block.timestamp
        );
        totalLiquidity = totalLiquidity.add(ethAmount);
    }

    /// This method is responsible for taking all fee, if takeFee is true
    /// @param sender is the address of account which will send the tokens
    /// @param recipient is the address of the account which will receive the tokens
    /// @param amount is the quantity to transfer
    function _tokenTransfer(address sender, address recipient, uint256 amount) private {
        if (_isExcludedFromReward[sender] && !_isExcludedFromReward[recipient]) {
            _transferFromExcluded(sender, recipient, amount);
        } else if (!_isExcludedFromReward[sender] && _isExcludedFromReward[recipient]) {
            _transferToExcluded(sender, recipient, amount);
        } else if (!_isExcludedFromReward[sender] && !_isExcludedFromReward[recipient]) {
            _transferStandard(sender, recipient, amount);
        } else if (_isExcludedFromReward[sender] && _isExcludedFromReward[recipient]) {
            _transferBothExcluded(sender, recipient, amount);
        } else {
            _transferStandard(sender, recipient, amount);
        }
    }

    /// This function sends token from sender to recipient
    /// @param sender is the account that sends tokens
    /// @param recipient is the account that will receive tokens
    /// @param tAmount is the quantity to send
    function _transferStandard(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, uint256 tLiquidity, uint256 tVault) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _takeLiquidity(tLiquidity);
        _takeVault(tVault);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    /// This function sends token from sender to excluded from reward recipient
    /// @param sender is the account that sends tokens
    /// @param recipient is the account that will receive tokens
    /// @param tAmount is the quantity to send
    function _transferToExcluded(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, uint256 tLiquidity, uint256 tVault) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _takeLiquidity(tLiquidity);
        _takeVault(tVault);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    /// This function sends token from excluded from reward sender to recipient
    /// @param sender is the account that sends tokens
    /// @param recipient is the account that will receive tokens
    /// @param tAmount is the quantity to send
    function _transferFromExcluded(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, uint256 tLiquidity, uint256 tVault) = _getValues(tAmount);
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _takeLiquidity(tLiquidity);
        _takeVault(tVault);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    /// This function add liquidity into the contract for rOwned and tOwned (if account is excluded from reward)
    /// of the contract account
    /// @param tLiquidity quantity of liquidity to add
    function _takeLiquidity(uint256 tLiquidity) private {
        uint256 currentRate =  _getRate();
        uint256 rLiquidity = tLiquidity.mul(currentRate);
        _rOwned[address(this)] = _rOwned[address(this)].add(rLiquidity);
        if(_isExcludedFromReward[address(this)])
            _tOwned[address(this)] = _tOwned[address(this)].add(tLiquidity);
    }

    /// This function add to vault the fee correspondant for it
    /// @param tVault quantity of tokens to add in vault
    function _takeVault(uint256 tVault) private {
        uint256 currentRate =  _getRate();
        uint256 rVault = tVault.mul(currentRate);
        _rOwned[blackHoleVaultAddress] = _rOwned[blackHoleVaultAddress].add(rVault);
        if(_isExcludedFromReward[address(this)])
            _tOwned[blackHoleVaultAddress] = _tOwned[blackHoleVaultAddress].add(tVault);
        emit Transfer(_msgSender(), blackHoleVaultAddress, tVault);
    }

    /// This function calls _getTvalues and _getRValues to obtain all the values
    /// @return the same values returned in _getTValues and _getRValues
    function _getValues(uint256 tAmount) private view returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256) {
        (uint256 tTransferAmount, uint256 tFee, uint256 tLiquidity, uint256 tVault) = _getTValues(tAmount);
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(tAmount, tFee, tLiquidity, tVault, _getRate());
        return (rAmount, rTransferAmount, rFee, tTransferAmount, tFee, tLiquidity, tVault);
    }

    /// This function is used to calculate different tValues with tAmount
    /// @param tAmount the value which is used to calculate
    /// @return tFee Value calculated with tax fee percentaje over tAmount
    /// @return tLiquidity Value calculated with liquidity fee percentaje over tAmount
    /// @return tLiquidity Value calculated with vault fee percentaje over tAmount
    /// @return tTransferAmount value extracted from the subtraction of tFee, tLiquidity and tVault over tAmount
    function _getTValues(uint256 tAmount) private view returns (uint256, uint256, uint256, uint256) {
        (uint256 tFee, uint256 tLiquidity, uint256 tVault) = calculateFees(tAmount);
        uint256 tTransferAmount = tAmount.sub(tFee).sub(tLiquidity).sub(tVault);
        return (tTransferAmount, tFee, tLiquidity, tVault);
    }

    /// This function obtains the rate calculated with the current supply
    /// @return rate obtained with rSupply / tSupply
    function _getRate() private view returns(uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply.div(tSupply);
    }

    /// This function calculates rSupply and tSupply considering whether the account
    /// is excluded from the reward or not
    /// @return rSupply and tSupply || _rTotal and _tTotal depending on the conditions
    function _getCurrentSupply() private view returns(uint256, uint256) {
        uint256 tSupply = _tTotal;  // add totalburned to avoid a decrease on reflection
        uint256 rSupply = _rTotal;
        for (uint256 i = 0; i < _excludedFromReward.length; i++) {
            if (_rOwned[_excludedFromReward[i]] > rSupply || _tOwned[_excludedFromReward[i]] > tSupply) return (_rTotal, _tTotal);
            rSupply = rSupply.sub(_rOwned[_excludedFromReward[i]]);
            tSupply = tSupply.sub(_tOwned[_excludedFromReward[i]]);
        }
        if (rSupply < _rTotal.div(_tTotal)) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }

    /// This functions calculates fees for an amount
    /// @param _amount the quantity to calculate its fee
    /// @return fees for holders, liquidity and vault
    function calculateFees(uint256 _amount) private view returns (uint256, uint256, uint256){
        uint256 tFee = _amount.mul(_holderFee).div(10**2);
        uint256 tLiquidity = _amount.mul(_liquidityFee).div(10**2);
        uint256 tVault = _amount.mul(_vaultFee).div(10**2);
        return (tFee, tLiquidity, tVault);
    }

    /// This function is used to calculate different tValues with tValues and the current rate
    /// @param tAmount the value which is used to calculate
    /// @param tFee is the tax fee of tAmount
    /// @param tLiquidity is the liquidity fee of tAmount
    /// @param currentRate rate obtained with the division rSupply / tSupply
    /// @return rAmount the result obtained by multiplying tAmount by currentRate
    /// @return rTransferAmount value extracted from the subtraction of rFee and rLiquidity over rAmount
    /// @return tTransferAmount value extracted from the subtraction of tFee and tLiquidity over tAmount
    function _getRValues(uint256 tAmount, uint256 tFee, uint256 tLiquidity, uint256 tVault, uint256 currentRate) private pure returns (uint256, uint256, uint256) {
        uint256 rAmount = tAmount.mul(currentRate);
        uint256 rFee = tFee.mul(currentRate);
        uint256 rLiquidity = tLiquidity.mul(currentRate);
        uint256 rTransferAmount = rAmount.sub(rFee).sub(rLiquidity).sub(tVault.mul(currentRate));
        return (rAmount, rTransferAmount, rFee);
    }
}
