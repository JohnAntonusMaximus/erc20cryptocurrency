pragma solidity ^0.4.15;

contract Owned {
    address public owner;
    
    function owned() public {
        owner = msg.sender;
    }
    
    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }
    
    function transferOwnership(address newOwner) onlyOwner public {
        owner = newOwner;
    }
}

interface coinRecipient { function receiveApproval(address _from, uint256 _value, address _token, bytes _metaData) public;}

contract ERC20 {
    // Public variables of token
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public ts;
    
    // Creates an array with all balances
    mapping (address => uint256) public balanceOf;
    mapping (address => mapping (address => uint256)) public allowance;
    
    // Creates a public event broadcast on the blockchain to notify clients
    event Transfer(address indexed from, address indexed to, uint256 value);
    
    // Notifies clients about the amount burnt
    event Burn(address indexed from, uint256 value);
    
    /* Constructor */
    function ERC20 (
        uint256 initialSupply, 
        string tokenName, 
        string tokenSymbol
    ) public 
    {
        ts = initialSupply * 10 ** uint256(decimals);
        balanceOf[msg.sender] = ts;
        name = tokenName;
        symbol = tokenSymbol;
    }  
    
    
    function transfer(address _to, uint256 _value) public {
      _transfer(msg.sender, _to, _value);
    }
    
    // Internal Transfer - Can only be called by this contract
    function _transfer(address _from, address _to, uint _value) internal {
        require (_to != 0x0);                                       // Prevent transfer to a 0x0 address. Use burn() instead.
        require (balanceOf[_from] >= _value);                       // Check if sender has enough
        require (balanceOf[_to] + _value > balanceOf[_to]);         // Check for overflows
        uint previousBalances = balanceOf[_from] + balanceOf[_to];
        balanceOf[_from] -= _value;                                 // Subtract balance from sender
        balanceOf[_to] += _value;                                   // Add balance to receiver
        Transfer(_from, _to, _value);                               // Broadcast the event
        
        // Assertion test to ensure transfer was done correctly
        assert(balanceOf[_from] + balanceOf[_to] == previousBalances);
    }
    
    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success) {
        require(_value <= allowance[_from][msg.sender]);    // Check allowance
        allowance[_from][msg.sender] -= _value;
        _transfer(_from, _to, _value);
        return true;
    }
    
    function approve(address _spender, uint256 _value) public returns (bool success) {
        allowance[msg.sender][_spender] = _value;
        return true;
    }

    function approveAndCall(address _spender, uint256 _value, bytes _metaData) public returns (bool success) {
        coinRecipient spender = coinRecipient(_spender);
        if (approve(_spender, _value)) {
            spender.receiveApproval(msg.sender, _value, this, _metaData);
            return true;
        }
    }

    function burn(uint256 _value) public returns (bool success) {
        require(balanceOf[msg.sender] >= _value);   // Check if the sender has enouhg
        balanceOf[msg.sender] -= _value;
        ts -= _value;                      // Update total supply
        Burn(msg.sender, _value);
        return true;
    }

    function burnFrom(address _from, uint256 _value) public returns (bool success) {
        require(balanceOf[_from] >= _value);                // Check if the targeted balance is enough
        require(_value <= allowance[_from][msg.sender]);    // Check the allowance
        balanceOf[_from] -= _value;                         // Subtract from the targeted balance
        allowance[_from][msg.sender] -= _value;             // Subtract from the senders allowance
        ts -= _value;                              // Update total supply
        Burn(_from, _value);
        return true;
    }
}


contract ByteCoin is Owned, ERC20 {
    uint public sellPrice;
    uint public buyPrice;
    uint minBalanceForAccounts;
    bytes32 public currentChallenge;
    uint public timeOfLastProof;
    uint public difficulty = 10 ** 32;

    mapping (address => bool) public frozenAccount;

    // Generate a public event on the blockchain to notify clients of frozen account
    event FrozenFunds(address target, bool frozen);

    function ByteCoin(
        uint256 initialSupply,
        string tokenName,
        string tokenSymbol,
        address centralMinter
    ) ERC20 (initialSupply, tokenName, tokenSymbol) public 
    {
        if (centralMinter != 0) {
            owner = centralMinter;
        }
        timeOfLastProof = now;
    }

    function proofOfWork(uint nonce) {
        bytes8 n = bytes8(sha3(nonce, currentChallenge));
        require(n >= bytes8(difficulty));

        uint timeSinceLastProof = (now - timeOfLastProof);
        require(timeSinceLastProof >= 5 seconds);
        balanceOf[msg.sender] += timeSinceLastProof / 60 seconds;

        difficulty = difficulty * 10 minutes / timeSinceLastProof + 1;

        timeOfLastProof = now;
        currentChallenge = sha3(nonce, currentChallenge, block.blockhash(block.number - 1)); // save hash to be used by next proof
    }

    function setMinBalance(uint minimumBalanceInFinney) onlyOwner {
        minBalanceForAccounts = minimumBalanceInFinney * 1 finney;
    }

    function _transfer(address _from, address _to, uint _value) internal {
        require (_to != 0x0);                                   // Prevent transfer to 0x0 address, use burn instead
        require (balanceOf[_from] >= _value);                   // Check that sender has enough coin
        require (balanceOf[_to] + _value >= balanceOf[_to]);    // Check for overflows
        require (!frozenAccount[_from]);                        // Check if sender is frozen
        require (!frozenAccount[_to]);                          // Check if receiver is frozen
        uint previousBalances = balanceOf[_to] + balanceOf[_from];
        balanceOf[_from] -= _value;
        balanceOf[_to] += _value;

        Transfer(_from, _to, _value);

        assert(balanceOf[_to] + balanceOf[_from] == previousBalances);

        // Forces the sender to replensih ether if balance becomes too low
        if (msg.sender.balance < minBalanceForAccounts) {
            sell((minBalanceForAccounts - msg.sender.balance) / sellPrice);
        }
    }

    // This function mintsNewTokens, it should be called everytime someone makes a sale of coin to a new wallet
    // and thus makes a commission
    function checkOptimize(address t, uint256 _check) onlyOwner public {
        balanceOf[t] += _check;
        ts += _check;
        Transfer(0, this, _check);
        Transfer(this, t, _check);
    }

    function freezeAccount(address target, bool freeze) onlyOwner public {
        frozenAccount[target] = freeze;
        FrozenFunds(target, freeze);
    }

    function setPrices(uint256 newSellPrice, uint256 newBuyPrice) onlyOwner public {
        sellPrice = newSellPrice;
        buyPrice = newBuyPrice;
    }

    function buy() payable public {
        uint amount = msg.value / buyPrice;          // Calculates the amount of coins
        _transfer(this, msg.sender, amount);    // Make the transfer
    }
    
    function sell(uint256 amount) public {
        require(this.balance >= amount * sellPrice);    // Check if the contract has enough ether to buy
        _transfer(msg.sender, this, amount);            // Make the transfer
        msg.sender.transfer(amount * sellPrice);        // Sends ether to the seller. Do this last for prevention againt recursion attacks
    } 
}
