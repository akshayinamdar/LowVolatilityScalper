//+------------------------------------------------------------------+
//|                                                  RandomTrader.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

//--- Input Parameters
input group "Trading Schedule"
input int MaxDailyTrades = 5;              // Number of trades per day
input string DailyStartTime = "08:00";     // Daily start time (HH:MM)
input string DailyEndTime = "20:00";       // Daily end time (HH:MM)
input int MinTimeBetweenTrades = 30;       // Minimum minutes between trades
input int MaxRandomDelay = 60;             // Maximum random delay minutes

input group "Risk Management"
input double RiskPercent = 1.0;            // Risk percentage (%)
input double FixedLotSize = 0.0;           // Fixed lot size (0 = auto calculate)
input int StopLossPips = 50;               // Stop loss in pips
input int TakeProfitPips = 100;            // Take profit in pips

//--- Global Variables
int dailyTradeCount = 0;
datetime nextTradeTime = 0;
datetime currentDay = 0;
bool hasOpenPosition = false;
ulong currentPositionTicket = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("RandomTrader EA initialized");
    
    // Initialize random seed with conditional approach
    if(MQLInfoInteger(MQL_TESTER)) {
        // Backtest-friendly random seed
        MathSrand((int)TimeCurrent() + (int)(SymbolInfoDouble(_Symbol, SYMBOL_BID)*1000));
    } else {
        // Live trading seed
        MathSrand(GetTickCount());
    }
    
    // Schedule first trade
    ScheduleNextTrade();
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                               |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("RandomTrader EA deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check if it's a new day and reset counters
    CheckNewDay();
    
    // Update position status
    UpdatePositionStatus();
    
    // Check if it's time to place a trade
    if(TimeCurrent() >= nextTradeTime && !hasOpenPosition)
    {
        CheckAndPlaceTrade();
    }
}

//+------------------------------------------------------------------+
//| Check if new day and reset counters                             |
//+------------------------------------------------------------------+
void CheckNewDay()
{
    datetime today = TimeCurrent() - (TimeCurrent() % 86400); // Start of today
    
    if(currentDay != today)
    {
        currentDay = today;
        dailyTradeCount = 0;
        hasOpenPosition = false;
        currentPositionTicket = 0;
        
        // Schedule first trade of the day
        ScheduleNextTrade();
        
        Print("New trading day started. Daily trade count reset.");
    }
}

//+------------------------------------------------------------------+
//| Update position status                                           |
//+------------------------------------------------------------------+
void UpdatePositionStatus()
{
    if(hasOpenPosition && currentPositionTicket > 0)
    {
        // Check if position still exists
        if(!PositionSelectByTicket(currentPositionTicket))
        {
            // Position was closed
            hasOpenPosition = false;
            currentPositionTicket = 0;
            
            Print("Position closed. Scheduling next trade.");
            
            // Schedule next trade after position closes
            if(dailyTradeCount < MaxDailyTrades && IsWithinTradingHours())
            {
                ScheduleNextTrade();
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Schedule next trade time                                         |
//+------------------------------------------------------------------+
void ScheduleNextTrade()
{
    if(dailyTradeCount >= MaxDailyTrades)
    {
        Print("Daily trade limit reached. No more trades scheduled.");
        return;
    }
    
    // Calculate next trade time
    int delayMinutes = MinTimeBetweenTrades + (MathRand() % MaxRandomDelay);
    nextTradeTime = TimeCurrent() + (delayMinutes * 60);
    
    string nextTradeTimeStr = TimeToString(nextTradeTime, TIME_DATE|TIME_MINUTES);
    Print("Next trade scheduled at: ", nextTradeTimeStr, " (in ", delayMinutes, " minutes)");
}

//+------------------------------------------------------------------+
//| Check if within trading hours                                   |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    // Convert string times to comparable format
    int startHour = (int)StringToInteger(StringSubstr(DailyStartTime, 0, 2));
    int startMinute = (int)StringToInteger(StringSubstr(DailyStartTime, 3, 2));
    int endHour = (int)StringToInteger(StringSubstr(DailyEndTime, 0, 2));
    int endMinute = (int)StringToInteger(StringSubstr(DailyEndTime, 3, 2));
    
    int currentMinutes = dt.hour * 60 + dt.min;
    int startMinutes = startHour * 60 + startMinute;
    int endMinutes = endHour * 60 + endMinute;
    
    return (currentMinutes >= startMinutes && currentMinutes <= endMinutes);
}

//+------------------------------------------------------------------+
//| Check conditions and place trade                                |
//+------------------------------------------------------------------+
void CheckAndPlaceTrade()
{
    // Check basic trading conditions
    if(!IsWithinTradingHours())
    {
        Print("Outside trading hours. Trade skipped.");
        // Reschedule for next day or later in the day
        if(dailyTradeCount < MaxDailyTrades)
            ScheduleNextTrade();
        return;
    }
    
    if(dailyTradeCount >= MaxDailyTrades)
    {
        Print("Daily trade limit reached.");
        return;
    }
    
    if(hasOpenPosition)
    {
        Print("Position already open. Trade skipped.");
        return;
    }
    
    // Random direction selection
    bool isLong = (MathRand() % 2 == 0);
    
    PlaceTrade(isLong);
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk percentage                     |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
    // If fixed lot size is specified, use it
    if(FixedLotSize > 0)
        return FixedLotSize;
    
    // Calculate lot size based on risk percentage
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = accountBalance * (RiskPercent / 100.0);
    
    // Get pip value for the symbol
    double pipValue = _Point;
    if(_Digits == 5 || _Digits == 3) pipValue *= 10;
    
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    
    // Calculate pip value in account currency
    double pipValueInAccountCurrency = (pipValue / tickSize) * tickValue;
    
    // Calculate total risk for stop loss distance
    double totalRisk = StopLossPips * pipValueInAccountCurrency;
    
    // Calculate lot size
    double calculatedLotSize = riskAmount / totalRisk;
    
    // Apply symbol constraints
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    // Normalize to lot step
    calculatedLotSize = NormalizeDouble(calculatedLotSize / lotStep, 0) * lotStep;
    
    // Ensure within limits
    if(calculatedLotSize < minLot) calculatedLotSize = minLot;
    if(calculatedLotSize > maxLot) calculatedLotSize = maxLot;
    
    Print("Risk calculation - Account: $", accountBalance, ", Risk: ", RiskPercent, "% ($", riskAmount, 
          "), SL: ", StopLossPips, " pips, Calculated lot: ", calculatedLotSize);
    
    return calculatedLotSize;
}

//+------------------------------------------------------------------+
//| Place a trade in the specified direction                        |
//+------------------------------------------------------------------+
void PlaceTrade(bool isLong)
{
    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);
    ZeroMemory(result);
    
    double price = isLong ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : 
                           SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    // Calculate stop loss and take profit
    double pipValue = _Point;
    if(_Digits == 5 || _Digits == 3) pipValue *= 10;
    
    double stopLoss, takeProfit;
    
    if(isLong)
    {
        stopLoss = price - (StopLossPips * pipValue);
        takeProfit = price + (TakeProfitPips * pipValue);
    }
    else
    {
        stopLoss = price + (StopLossPips * pipValue);
        takeProfit = price - (TakeProfitPips * pipValue);
    }
    
    // Get calculated lot size
    double lotSize = CalculateLotSize();
    
    // Prepare trade request
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = lotSize;
    request.type = isLong ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    request.price = price;
    request.sl = stopLoss;
    request.tp = takeProfit;
    request.deviation = 3;
    request.magic = 54321;
    request.comment = "RandomTrader";
    
    // Send order
    if(OrderSend(request, result))
    {
        if(result.retcode == TRADE_RETCODE_DONE)
        {
            dailyTradeCount++;
            hasOpenPosition = true;
            currentPositionTicket = result.position;
            
            Print("Trade #", dailyTradeCount, " placed successfully. Direction: ", isLong ? "LONG" : "SHORT",
                  ", Price: ", price, ", Lot: ", lotSize, ", SL: ", stopLoss, ", TP: ", takeProfit);
        }
        else
        {
            Print("Trade failed. Return code: ", result.retcode, " - ", result.comment);
            // Reschedule next trade even if this one failed
            if(dailyTradeCount < MaxDailyTrades)
                ScheduleNextTrade();
        }
    }
    else
    {
        Print("OrderSend failed. Error: ", GetLastError());
        // Reschedule next trade even if this one failed
        if(dailyTradeCount < MaxDailyTrades)
            ScheduleNextTrade();
    }
}
