// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

library Address {
    function isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }
}

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

abstract contract Ownable is Context {
    address private _owner;
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    constructor() {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function renounceOwnership() public onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);
}

library SafeERC20 {
    using Address for address;

    function safeTransfer(
        IERC20 token,
        address to,
        uint256 value
    ) internal {
        callOptionalReturn(
            token,
            abi.encodeWithSelector(token.transfer.selector, to, value)
        );
    }

    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value
    ) internal {
        callOptionalReturn(
            token,
            abi.encodeWithSelector(token.transferFrom.selector, from, to, value)
        );
    }

    function safeApprove(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        require(
            (value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        callOptionalReturn(
            token,
            abi.encodeWithSelector(token.approve.selector, spender, value)
        );
    }

    function safeIncreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender) + value;
        callOptionalReturn(
            token,
            abi.encodeWithSelector(
                token.approve.selector,
                spender,
                newAllowance
            )
        );
    }

    function safeDecreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender) - value;
        callOptionalReturn(
            token,
            abi.encodeWithSelector(
                token.approve.selector,
                spender,
                newAllowance
            )
        );
    }

    function callOptionalReturn(IERC20 token, bytes memory data) private {
        require(address(token).isContract(), "SafeERC20: call to non-contract");
        (bool success, bytes memory returndata) = address(token).call(data);
        require(success, "SafeERC20: low-level call failed");
        if (returndata.length > 0) {
            require(
                abi.decode(returndata, (bool)),
                "SafeERC20: ERC20 operation did not succeed"
            );
        }
    }
}

contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

contract PublicSale is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address;

    IERC20 public rewardToken;
    mapping(address => bool) private whitelist; 
    bool public whitelistOnlyMode;

    mapping(address => uint256) public balance;
    mapping(address => bool) public isRefunded;
    mapping (address => uint256) public claimedTokenAmount;
    uint256[2] private unlockPeriod;

    uint256 private startTime;
    uint256 private endTime;
    uint256 private totalAmount;
    uint256 private targetAmount;
    uint256 private minPerTx;
    uint256 private maxPerTx;
    uint256 private maxPerAddress;
    uint256 private softCapAmount;
    uint256 private hardCapAmount;
    uint256 private price;

    event Join(address user, uint256 amount);
    event Refund(address user, uint256 amount);
    event ClaimToken(address user, uint256 amount);

    constructor() {
        rewardToken = IERC20(0xD68458f51cE9fEb238cdcf4CbcDdF010EEad01b4);
        targetAmount = 100 ether;
        minPerTx = 0.00001 ether;
        maxPerTx = 0.01 ether;
        maxPerAddress = 1 ether;
        softCapAmount = 0.1 ether;
        hardCapAmount = 200 ether;
        price = 0.000002 ether;
    }

    modifier checkWhiteMode() {
        if (whitelistOnlyMode) require(isWhiteAddr(_msgSender()));
        _;
    }

    //view
    function isWhiteAddr(address user) public view returns (bool) {
        return whitelist[user];
    }

    function getParameters()
        external
        view
        returns (
            uint256 _startTime,
            uint256 _endTime,
            uint256 _totalAmount,
            uint256 _targetAmount,
            uint256 _minPerTx,
            uint256 _maxPerTx,
            uint256 _maxPerAddress,
            uint256 _softCapAmount,
            uint256 _hardCapAmount,
            uint256 _price,
            uint256 unlockPeriod1,
            uint256 unlockPeriod2
        )
    {
        return (
            startTime,
            endTime,
            totalAmount,
            targetAmount,
            minPerTx,
            maxPerTx,
            maxPerAddress,
            softCapAmount,
            hardCapAmount,
            price,
            unlockPeriod[0],
            unlockPeriod[1]
        );
    }

    function join() external payable nonReentrant checkWhiteMode {
        require(
            startTime <= block.timestamp && block.timestamp < endTime,
            "WrongTime!"
        );
        uint256 amount = msg.value;
        require(minPerTx <= amount && amount <= maxPerTx, "InvalidValue!");
        balance[_msgSender()] += amount;
        require(
            balance[_msgSender()] <= maxPerAddress,
            "Exceeded participation limit!"
        );
        totalAmount += amount;
        
        if (hardCapAmount > 0 && totalAmount >= hardCapAmount) {
            endTime = block.timestamp;
            uint256 refundAmount = totalAmount - hardCapAmount;
            totalAmount = hardCapAmount;
            if (refundAmount > 0) {
                balance[_msgSender()] -= refundAmount;
                payable(_msgSender()).transfer(refundAmount);
                amount -= refundAmount;
            }
        }
        emit Join(_msgSender(), amount);
    }


    //claim Token
    function claimToken() external nonReentrant {
        
        uint256 claimableTokenAmount = calcClaimableTokenAmount(_msgSender());
        require(claimedTokenAmount[_msgSender()] < claimableTokenAmount, 'No tokens available to claim.');
        uint256 claimTokenAmont = claimableTokenAmount - claimedTokenAmount[_msgSender()];
        claimedTokenAmount[_msgSender()] = claimableTokenAmount;
        rewardToken.safeTransfer(_msgSender(), claimTokenAmont);
        emit ClaimToken(_msgSender(), claimTokenAmont);
    }
    
    function calcClaimableTokenAmount(address user) public view returns (uint256){
        require(block.timestamp > endTime, "WrongTime!");
        uint256 validAmount = calcValidAmount(user);
        uint256 tokenAmount = validAmount * 1e18 / price;
        uint256 claimableTokenAmount = 0;
        if (block.timestamp >= endTime + unlockPeriod[0] + unlockPeriod[1]){
            claimableTokenAmount = tokenAmount;
        }else if(block.timestamp >= endTime + unlockPeriod[0]){
            claimableTokenAmount = tokenAmount * 6 / 10;
        }else {
            claimableTokenAmount = tokenAmount * 3 / 10;
        }
        return  claimableTokenAmount;
    }

    function calcValidAmount(address user) public view returns (uint256) {
        
        if (block.timestamp > endTime && 0 < softCapAmount && totalAmount < softCapAmount ) return 0;
        uint256 userAmount = balance[user];
        if (userAmount == 0) return 0;
        
        return totalAmount > targetAmount ? targetAmount * userAmount / totalAmount : userAmount;
    }

    function refund() external nonReentrant {
        
        require(block.timestamp > endTime, "WrongTime!");
        require(!isRefunded[_msgSender()], "Refunded!");
        require(balance[_msgSender()] > 0, "Balance zero!");
        uint256 validAmount = calcValidAmount(_msgSender());
        uint256 refundAmount = balance[_msgSender()] - validAmount;
        isRefunded[_msgSender()] = true;
        if (refundAmount > 0) payable(_msgSender()).transfer(refundAmount);
        emit Refund(_msgSender(), refundAmount);
    }

    //---write onlyOwner---//

    function toggleWhiteMode() external onlyOwner {
        whitelistOnlyMode = !whitelistOnlyMode;
    }

    function setTime(uint256 _startTime, uint256 _endTime) external onlyOwner {
        startTime = _startTime;
        endTime = _endTime;
    }

    function setunLockPeriod(uint256[2] calldata _unlockPeriod) external onlyOwner {
         unlockPeriod = _unlockPeriod;
    }

    function setAmount(
        uint256 _targetAmount,
        uint256 _minPerTx,
        uint256 _maxPerTx,
        uint256 _maxPerAddress
    ) external onlyOwner {
        targetAmount = _targetAmount;
        minPerTx = _minPerTx;
        maxPerTx = _maxPerTx;
        maxPerAddress = _maxPerAddress;
    }

    function setCapAmount(uint256 _softCapAmount, uint256 _hardCapAmount)
        external
        onlyOwner
    {
        softCapAmount = _softCapAmount;
        hardCapAmount = _hardCapAmount;
    }

    function setPrice(uint256 _price) external onlyOwner {
        price = _price;
    }

    function addToWhitelist(address _address) external onlyOwner {
        whitelist[_address] = true;
    }

    function addToWhitelist(address[] calldata _addresses) external onlyOwner {
        for (uint256 i = 0; i < _addresses.length; i++) {
            whitelist[_addresses[i]] = true;
        }
    }

    function removeFromWhitelist(address _address) external onlyOwner {
        whitelist[_address] = false;
    }

    function removeFromWhitelist(address[] calldata _addresses)
        external
        onlyOwner
    {
        for (uint256 i = 0; i < _addresses.length; i++) {
            whitelist[_addresses[i]] = false;
        }
    }

    receive() external payable {}

    function withdraw(uint256 amount) external onlyOwner {
        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "Low-level call failed");
    }

    function withdrawToken(address tokenAddr, uint256 amount)
        external
        onlyOwner
    {
        IERC20 token = IERC20(tokenAddr);
        token.safeTransfer(owner(), amount);
    }
}
