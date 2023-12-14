//+------------------------------------------------------------------+
//|                                      Geoturtle Daily Chart EA     |
//|                                      Developed by ChatGPT         |
//+------------------------------------------------------------------+

#property copyright "Georgeo"
#property link      "Georgeo"
#property version   "2.0"
#property description "Geoturtle Daily Chart"

// Declare input parameters
input int BreakoutPeriod = 20; // N-day breakout period
input int ExitPeriod = 10; // M-day exit period
input double ATRMultiplier = 2.0; // Multiplier for ATR-based stop loss
input double RiskPercent = 2.0; // Risk percentage per trade
input double LotSize = 0.1; // Lot size for each trade
input double CloseProfitPercent = 10.0; // Percentage of balance to trigger closing all orders
input int Slippage = 3; // Slippage in points
input bool UseStopLoss = true; // Enable or disable the use of stop loss
input bool ModifyStopLoss = true; // Enable or disable the modification of stop loss
input double StopLossMultiplier = 2.0; // Multiplier for ATR-based stop loss

// Add the new input parameters for risk management
input double MaxDailyLossPercent = 10.0; // Maximum daily loss percent of the balance
input double MaxTradeLossPercent = 2.0; // Maximum trade loss percent of the balance
input int MinTimeBetweenTrades = 180; // Minimum time between trades in seconds


// Declare global variables
double BuyBreakoutLevel;
double SellBreakoutLevel;
double BuyExitLevel;
double SellExitLevel;
double ATRValue;
double AccountRisk;
double PointSize;

// Global variables for new risk management features
double DayStartBalance = 0;
datetime LastTradeTime = 0;
double MaxDailyLoss = 0;
double MaxTradeLoss = 0;
int TotalOpenTrades = 0;

// Initialization function
int OnInit() {
  DayStartBalance = AccountBalance(); // Balance at the start of the day
  MaxDailyLoss = DayStartBalance * (MaxDailyLossPercent / 100);
  MaxTradeLoss = DayStartBalance * (MaxTradeLossPercent / 100);
  // ... other initialization code
  return(INIT_SUCCEEDED);
}

int start() {

  // Risk management checks
  if (AccountBalance() - DayStartBalance <= -MaxDailyLoss) {
    Print("Maximum daily loss reached. No more trading today.");
    return(0); // Exit the function, no further trading allowed
  }
  if (TimeCurrent() - LastTradeTime < MinTimeBetweenTrades) {
    return(0); // Exit the function, not enough time passed since the last trade
  }
  // Calculate account risk in terms of balance
  AccountRisk = AccountBalance() * RiskPercent / 100;
  
  // Calculate ATR
  ATRValue = iATR(NULL, PERIOD_D1, 30, 0);
  
  // Calculate point size based on the currency pair
  PointSize = MarketInfo(Symbol(), MODE_POINT);
  
  // Calculate breakout and exit levels
  CalculateBreakoutLevels();
  
  // Check for entry and exit signals
  EntrySignals();
  ExitSignals();
  
  // Set stop loss for existing orders
  SetStopLoss();
  
  // Check profit and potentially close all orders
   CheckAndCloseAllOrders();
   
   // After finishing the trade logic, update the LastTradeTime
  LastTradeTime = TimeCurrent();
  
  return(0);
}
// Function to calculate the N value (20-day ATR)
double CalculateN() {
    return iATR(NULL, PERIOD_D1, 20, 0);
}

// Function to calculate position size based on account equity and N
double CalculatePositionSize(double N) {
    double accountRisk = AccountEquity() * 0.01; // 1% of account equity
    double dollarVolatility = N * MarketInfo(Symbol(), MODE_TICKVALUE);
    return accountRisk / dollarVolatility;
}

// Function to place an order with position sizing
void PlaceOrder(int type, double breakoutLevel, double N) {
    double positionSize = CalculatePositionSize(N);
    double stopLoss = (type == OP_BUY) ? breakoutLevel - 2 * N : breakoutLevel + 2 * N;
    int ticket = OrderSend(Symbol(), type, positionSize, breakoutLevel, Slippage, stopLoss, 0, "Turtle Trade", 0, 0, (type == OP_BUY) ? Blue : Red);
    if (ticket < 0) {
        Print("OrderSend failed with error: ", GetLastError());
    } else {
        // Set the LastTradeTime to the current time after opening a new position
        LastTradeTime = TimeCurrent();
    }
}

// Function to modify the stop loss for an existing trade
void ModifyStopLossForTrade(int ticket, double newStopLoss) {
    if (OrderSelect(ticket, SELECT_BY_TICKET) && OrderType() <= OP_SELL) {
      bool success = OrderModify(ticket, OrderOpenPrice(), newStopLoss, OrderTakeProfit(), 0, clrRed);
        if (!success) {
            Print("Error modifying stop loss for ticket #", ticket, ": ", GetLastError());
        }
    }
}


// Function to check profits and close all orders if necessary
void CheckAndCloseAllOrders() {
   double balance = AccountBalance();
   double equity = AccountEquity();

   // Check if total profit exceeds the specified percentage of balance
   double closeProfitThreshold = (CloseProfitPercent / 100.0) * balance;
   if ((equity - balance) >= closeProfitThreshold) {
      CloseAllOrders();
   }
}

// Function to close all orders
void CloseAllOrders() {
   int totalOrders = OrdersTotal();
   bool hasClosedAnyOrder = false; // Flag to check if any order has been closed

   // Iterate through all orders to close them
   for (int i = totalOrders - 1; i >= 0; i--) {
      if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
         // Check if the order is for the current symbol and type
         if(OrderSymbol() == Symbol() && (OrderType() == OP_BUY || OrderType() == OP_SELL)) {
            int closeResult = OrderClose(OrderTicket(), OrderLots(), MarketInfo(OrderSymbol(), (OrderType() == OP_BUY) ? MODE_BID : MODE_ASK), Slippage, clrNONE);
            if (closeResult >= 0) {
               hasClosedAnyOrder = true;
               // Update last trade time after closing each order
               LastTradeTime = TimeCurrent();
               Print("Order closed: ", OrderTicket());
            } else {
               Print("Error in OrderClose (Ticket ", OrderTicket(), "): ", GetLastError());
            }
         }
      }
   }

   // If any order has been closed, print the summary
   if(hasClosedAnyOrder) {
      Print("One or more orders have been closed.");
   } else {
      Print("No orders were closed.");
   }
}



// Function to calculate breakout levels
void CalculateBreakoutLevels() {
  // Ensure we have enough bars to calculate the levels
  if (Bars < BreakoutPeriod || Bars < ExitPeriod) {
    Print("Not enough bars to calculate levels. Bars: ", Bars);
    return;
  }

  BuyBreakoutLevel = High[iHighest(NULL, PERIOD_D1, MODE_HIGH, BreakoutPeriod, 1)];
  SellBreakoutLevel = Low[iLowest(NULL, PERIOD_D1, MODE_LOW, BreakoutPeriod, 1)];
  BuyExitLevel = Low[iLowest(NULL, PERIOD_D1, MODE_LOW, ExitPeriod, 1)];
  SellExitLevel = High[iHighest(NULL, PERIOD_D1, MODE_HIGH, ExitPeriod, 1)];
  
  // Adding a buffer to ensure exit levels are not too close to current price
  double buffer = ATRValue * 0.5; // Half ATR as a buffer
  BuyExitLevel -= buffer; // Adjusting BuyExitLevel to be lower
  SellExitLevel += buffer; // Adjusting SellExitLevel to be higher

  Print("BuyBreakoutLevel: ", BuyBreakoutLevel, " SellBreakoutLevel: ", SellBreakoutLevel, 
        " BuyExitLevel: ", BuyExitLevel, " SellExitLevel: ", SellExitLevel);
}

// Function to check entry signals
void EntrySignals() {
  double AskPrice = MarketInfo(Symbol(), MODE_ASK);
  double BidPrice = MarketInfo(Symbol(), MODE_BID);

  // Check for Buy signal
  if (AskPrice > BuyBreakoutLevel && OrdersTotal() == 0 && UseStopLoss) {
    double BuyStopLoss = AskPrice - ATRValue * StopLossMultiplier * PointSize;
    int BuyTicket = OrderSend(Symbol(), OP_BUY, LotSize, AskPrice, Slippage, BuyStopLoss, 0, "Turtle Buy", 0, 0, Green);
    if (BuyTicket < 0) {
      Print("Buy order failed with error: ", GetLastError());
    } else {
      Print("Buy order placed with SL at: ", BuyStopLoss);
    }
  }
  
  // Check for Sell signal
  if (BidPrice < SellBreakoutLevel && OrdersTotal() == 0 && UseStopLoss) {
    double SellStopLoss = BidPrice + ATRValue * StopLossMultiplier * PointSize;
    int SellTicket = OrderSend(Symbol(), OP_SELL, LotSize, BidPrice, Slippage, SellStopLoss, 0, "Turtle Sell", 0, 0, Red);
    if (SellTicket < 0) {
      Print("Sell order failed with error: ", GetLastError());
    } else {
      Print("Sell order placed with SL at: ", SellStopLoss);
    }
  }
}


// Function to check exit signals
void ExitSignals() {
  bool closed; // Declare once at the beginning of the function
  for (int i = 0; i < OrdersTotal(); i++) {
    if (OrderSelect(i, SELECT_BY_POS) && OrderSymbol() == Symbol()) {
      double CurrentPrice = MarketInfo(Symbol(), MODE_BID);
      
      // Check if it's time to close a Buy order
      if (OrderType() == OP_BUY && CurrentPrice <= BuyExitLevel) {
        closed = OrderClose(OrderTicket(), OrderLots(), CurrentPrice, 3, White);
      }
      
      // Check if it's time to close a Sell order
      CurrentPrice = MarketInfo(Symbol(), MODE_ASK);
      if (OrderType() == OP_SELL && CurrentPrice >= SellExitLevel) {
        closed = OrderClose(OrderTicket(), OrderLots(), CurrentPrice, 3, White);
      }
    }
  }
}

// Function to set stop loss for existing orders
void SetStopLoss() {
  bool modified;
  for (int i = 0; i < OrdersTotal(); i++) {
      if (OrderSelect(i, SELECT_BY_POS) && OrderSymbol() == Symbol()) {
      double newStopLoss = 0;
      double orderOpenPrice = OrderOpenPrice();

      // Adjust Stop Loss for Buy orders
     if (OrderType() == OP_BUY && ModifyStopLoss) {
         newStopLoss = orderOpenPrice - ATRValue * ATRMultiplier * PointSize;
         if (OrderStopLoss() > newStopLoss) { // For buy orders, new SL must be less than current SL
         modified = OrderModify(OrderTicket(), orderOpenPrice, newStopLoss, OrderTakeProfit(), 0, Blue);
         if (!modified) Print("OrderModify failed with error: ", GetLastError());
        }
      }

      // Adjust Stop Loss for Sell orders
      if (OrderType() == OP_SELL && ModifyStopLoss) {
          newStopLoss = orderOpenPrice + ATRValue * ATRMultiplier * PointSize;
          if (OrderStopLoss() < newStopLoss) { // For sell orders, new SL must be greater than current SL
          modified = OrderModify(OrderTicket(), orderOpenPrice, newStopLoss, OrderTakeProfit(), 0, Red);
          if (!modified) Print("OrderModify failed with error: ", GetLastError());
        }
      }
    }
  }
}

