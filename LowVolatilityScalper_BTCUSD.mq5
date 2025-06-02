//+------------------------------------------------------------------+
//|                                   LowVolatilityScalper_BTCUSD.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

//--- Input Parameters
input group "Trading Limits"
input int MaxConcurrentTrades = 2;           // Maximum concurrent trades
input int MaxDailyTrades = 10;               // Maximum trades per day
input string DailyStartTime = "00:00";       // Daily start time (HH:MM)
input string DailyEndTime = "23:59";         // Daily end time (HH:MM)

input group "Market Checking Mechanism"
input int CheckFrequency = 2;                // Checks per hour
input bool RandomCheckWindow = true;         // Enable random check times
input int MinTimeBetweenChecks = 15;         // Min minutes between checks
input int MaxTimeBetweenChecks = 40;         // Max minutes between checks

input group "Trading Parameters"
input double LotSize = 0.001;                // Position size (smaller for BTC)
input int ProfitTargetPips = 50;             // Profit target in points
input int StopLossPips = 100;                // Stop loss in points
input int VolatilityPeriod = 60;             // Minutes to check volatility
input int VolatilityRange = 200;             // Maximum range in points (wider for BTC)

input group "Risk Management"
input double MaxRiskPercent = 1.0;           // Maximum risk per trade (%)

input group "Trailing Stop Settings"
input double TrailingActivationPips = 25;   // Activate after X points profit
input double TrailingPercent = 40.0;        // Trail by % of profit

//--- Global Variables
int dailyTradeCount = 0;
datetime lastCheckTime = 0;
datetime nextCheckTime = 0;
datetime currentDay = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("Low Volatility Scalper EA for BTCUSD initialized");
    
    // Initialize random seed with conditional approach
    if(MQLInfoInteger(MQL_TESTER)) {
        // Backtest-friendly random seed
        MathSrand((int)TimeCurrent() + (int)(SymbolInfoDouble(_Symbol, SYMBOL_BID)*1000));
    } else {
        // Live trading seed
        MathSrand(GetTickCount());
    }
    
    // Set next check time
    ScheduleNextCheck();
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                               |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("Low Volatility Scalper EA for BTCUSD deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check if it's a new day and reset daily counter
    CheckNewDay();
    
    // Only check market at scheduled times
    if(TimeCurrent() >= nextCheckTime)
    {
        CheckMarketConditions();
        ScheduleNextCheck();
    }
    
    // Monitor existing positions
    MonitorPositions();
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
        Print("New trading day started. Daily trade count reset.");
    }
}

//+------------------------------------------------------------------+
//| Schedule next market check                                       |
//+------------------------------------------------------------------+
void ScheduleNextCheck()
{
    int minutesToNext;
    
    if(RandomCheckWindow)
    {
        // Random interval between min and max
        minutesToNext = MinTimeBetweenChecks + 
                       MathRand() % (MaxTimeBetweenChecks - MinTimeBetweenChecks + 1);
    }
    else
    {
        // Fixed interval based on frequency
        minutesToNext = 60 / CheckFrequency;
    }
    
    nextCheckTime = TimeCurrent() + (minutesToNext * 60);
    lastCheckTime = TimeCurrent();

    string nextCheckTimeStr = TimeToString(nextCheckTime, TIME_DATE|TIME_MINUTES);
    Print("Next market check scheduled at: ", nextCheckTimeStr, " (in ", minutesToNext, " minutes)");
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
//| Check market conditions and place trade if criteria met         |
//+------------------------------------------------------------------+
void CheckMarketConditions()
{
    // Check basic trading conditions
    if(!IsWithinTradingHours())
        return;
        
    if(dailyTradeCount >= MaxDailyTrades)
        return;
        
    if(GetCurrentPositionCount() >= MaxConcurrentTrades)
        return;
    
    // Check volatility conditions
    if(IsLowVolatilityPeriod())
    {
        // Use random direction selection
        bool isLong = (MathRand() % 2 == 0); // Random true/false
        PlaceTrade(isLong);
        Print("Low volatility detected. Random direction selected: ", isLong ? "LONG" : "SHORT");
    }
}

//+------------------------------------------------------------------+
//| Check if current period has low volatility (optimized for BTC)  |
//+------------------------------------------------------------------+
bool IsLowVolatilityPeriod()
{
    double high = 0, low = DBL_MAX;
    
    // Get high and low for the last VolatilityPeriod minutes
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    int copied = CopyRates(_Symbol, PERIOD_M1, 0, VolatilityPeriod, rates);
    
    if(copied > 0)
    {
        for(int i = 0; i < copied; i++)
        {
            if(rates[i].high > high) high = rates[i].high;
            if(rates[i].low < low) low = rates[i].low;
        }
    }
    
    // Calculate range in points (for BTC, we use _Point directly)
    double rangePoints = (high - low);
    
    Print("BTC Volatility Check - Range High: ", high, ", Range Low: ", low, ", Range Points: ", rangePoints);
    
    // Check if range is within our volatility threshold
    if(rangePoints <= VolatilityRange)
    {
        // Calculate boundaries for middle 60% of the range
        double rangeWidth = high - low;
        double lowerBoundary = low + (rangeWidth * 0.2);  // 20% from bottom
        double upperBoundary = high - (rangeWidth * 0.2); // 20% from top
        double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         
        Print("BTC Middle 60% Boundaries - Lower: ", lowerBoundary, ", Upper: ", upperBoundary, ", Current Price: ", currentPrice);
        
        // Check if price is within the middle 60%
        bool isWithinMiddle60Percent = (currentPrice >= lowerBoundary && currentPrice <= upperBoundary);
        
        return isWithinMiddle60Percent;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Place a trade in the specified direction (optimized for BTC)    |
//+------------------------------------------------------------------+
void PlaceTrade(bool isLong)
{
    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);
    ZeroMemory(result);
    
    double price = isLong ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : 
                           SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    // Get symbol point and minimum stops
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    int minStopLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
    
    // For BTC, ensure we have reasonable minimum distances
    double minDistance = MathMax(minStopLevel * point, 50 * point); // At least 50 points for BTC
    
    // Calculate stop loss and take profit distances  
    double slDistance = MathMax(StopLossPips * point, minDistance * 2); // Ensure SL is at least 2x min distance
    double tpDistance = MathMax(ProfitTargetPips * point, minDistance); // Ensure TP is at least min distance
    
    double stopLoss, takeProfit;
    
    if(isLong)
    {
        // Long position: SL below price, TP above price
        stopLoss = price - slDistance;
        takeProfit = price + tpDistance;
    }
    else
    {
        // Short position: SL above price, TP below price  
        stopLoss = price + slDistance;
        takeProfit = price - tpDistance;
    }
    
    // Normalize prices to tick size
    stopLoss = NormalizeDouble(stopLoss, _Digits);
    takeProfit = NormalizeDouble(takeProfit, _Digits);
    price = NormalizeDouble(price, _Digits);
    
    // Validate that stops are properly positioned
    bool validStops = true;
    if(isLong)
    {
        if(stopLoss >= price || takeProfit <= price)
            validStops = false;
    }
    else
    {
        if(stopLoss <= price || takeProfit >= price)
            validStops = false;
    }
    
    // Check minimum distances are respected
    double slDistanceCheck = MathAbs(price - stopLoss);
    double tpDistanceCheck = MathAbs(price - takeProfit);
    
    if(slDistanceCheck < minDistance || tpDistanceCheck < minDistance)
        validStops = false;
    
    if(!validStops)
    {
        Print("BTC Trade cancelled - Invalid stop levels. Price: ", price, 
              ", SL: ", stopLoss, ", TP: ", takeProfit, ", Min Distance: ", minDistance);
        return;
    }
    
    // Prepare trade request
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = LotSize;
    request.type = isLong ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    request.price = price;
    request.sl = stopLoss;
    request.tp = takeProfit;
    request.deviation = 10; // Wider deviation for crypto
    request.magic = 12346; // Different magic number for BTC EA
    request.comment = "BTC_LowVolScalper";
    
    Print("BTC Trade attempt - Direction: ", isLong ? "LONG" : "SHORT",
          ", Price: ", price, ", SL: ", stopLoss, ", TP: ", takeProfit,
          ", SL Distance: ", slDistanceCheck, ", TP Distance: ", tpDistanceCheck,
          ", Min Distance: ", minDistance);
    
    // Send order
    if(OrderSend(request, result))
    {
        if(result.retcode == TRADE_RETCODE_DONE)
        {
            dailyTradeCount++;
            Print("BTC Trade placed successfully. Direction: ", isLong ? "LONG" : "SHORT",
                  ", Price: ", price, ", SL: ", stopLoss, ", TP: ", takeProfit, 
                  ", Daily count: ", dailyTradeCount);
        }
        else
        {
            Print("BTC Trade failed. Return code: ", result.retcode, " - ", result.comment);
        }
    }
    else
    {
        Print("OrderSend failed for BTC. Error: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Get current number of open positions                            |
//+------------------------------------------------------------------+
int GetCurrentPositionCount()
{
    int count = 0;
    
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionSelectByTicket(PositionGetTicket(i)))
        {
            string posSymbol = PositionGetString(POSITION_SYMBOL);
            ulong posMagic = PositionGetInteger(POSITION_MAGIC);
            
            if(posSymbol == _Symbol && posMagic == 12346) // BTC EA magic number
                count++;
        }
    }
    
    return count;
}

//+------------------------------------------------------------------+
//| Monitor existing positions                                       |
//+------------------------------------------------------------------+
void MonitorPositions()
{
    // For crypto, we might want to keep positions open outside trading hours
    // Always process trailing stops
    ManageTrailingStops();
}

//+------------------------------------------------------------------+
//| Manage trailing stops for all open positions (BTC optimized)    |
//+------------------------------------------------------------------+
void ManageTrailingStops()
{
    double pointValue = _Point; // For BTC, use _Point directly
    
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionSelectByTicket(PositionGetTicket(i)))
        {
            string posSymbol = PositionGetString(POSITION_SYMBOL);
            ulong posMagic = PositionGetInteger(POSITION_MAGIC);
            
            // Only process our own positions on the current symbol
            if(posSymbol == _Symbol && posMagic == 12346)
            {
                double currentSL = PositionGetDouble(POSITION_SL);
                double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
                double currentPrice = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 
                                     SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                                     SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                
                // Calculate profit in points
                double profitPoints;
                if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                {
                    profitPoints = (currentPrice - openPrice) / pointValue;
                }
                else
                {
                    profitPoints = (openPrice - currentPrice) / pointValue;
                }
                
                // Only apply trailing stop if we've reached activation threshold
                if(profitPoints >= TrailingActivationPips)
                {
                    // Calculate trailing distance as percentage of profit
                    double trailingDistancePoints = profitPoints * (TrailingPercent / 100.0);
                    
                    // Ensure minimum trail distance of 5 points for BTC
                    if(trailingDistancePoints < 5.0) trailingDistancePoints = 5.0;
                    
                    double newSL;
                    bool modifyNeeded = false;
                    
                    if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                    {
                        // For buy positions, trail below the current price
                        newSL = currentPrice - (trailingDistancePoints * pointValue);
                        
                        // Only modify if the new SL is higher than the current one
                        if(newSL > currentSL)
                            modifyNeeded = true;
                    }
                    else
                    {
                        // For sell positions, trail above the current price
                        newSL = currentPrice + (trailingDistancePoints * pointValue);
                        
                        // Only modify if the new SL is lower than the current one
                        if(newSL < currentSL || currentSL == 0)
                            modifyNeeded = true;
                    }
                    
                    // Update the stop loss if needed
                    if(modifyNeeded)
                    {
                        Print("Updating BTC trailing stop for position #", PositionGetTicket(i), 
                              " Current profit: ", profitPoints, " points",
                              " Trail distance: ", trailingDistancePoints, " points");
                        ModifyStopLoss(PositionGetTicket(i), newSL);
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Modify stop loss for a position                                  |
//+------------------------------------------------------------------+
bool ModifyStopLoss(ulong ticket, double newSL)
{
    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);
    ZeroMemory(result);
    
    request.action = TRADE_ACTION_SLTP;
    request.position = ticket;
    request.symbol = _Symbol;
    request.sl = newSL;
    request.tp = PositionGetDouble(POSITION_TP); // Keep the same TP
    
    if(OrderSend(request, result))
    {
        if(result.retcode == TRADE_RETCODE_DONE)
        {
            Print("BTC Trailing stop updated for ticket #", ticket, " to ", newSL);
            return true;
        }
        else
        {
            Print("Failed to update BTC trailing stop. Error code: ", result.retcode);
        }
    }
    else
    {
        Print("OrderSend failed for BTC trailing stop. Error: ", GetLastError());
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Close all positions at end of trading day                       |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
    // Store position tickets first to avoid index issues
    ulong tickets[];
    int count = 0;
    
    // Collect tickets of positions to close
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionSelectByTicket(PositionGetTicket(i)))
        {
            string posSymbol = PositionGetString(POSITION_SYMBOL);
            ulong posMagic = PositionGetInteger(POSITION_MAGIC);
            
            if(posSymbol == _Symbol && posMagic == 12346)
            {
                ArrayResize(tickets, count + 1);
                tickets[count] = PositionGetTicket(i);
                count++;
            }
        }
    }
    
    // Close positions using stored tickets
    for(int i = 0; i < count; i++)
    {
        if(PositionSelectByTicket(tickets[i]))
        {
            MqlTradeRequest request;
            MqlTradeResult result;
            ZeroMemory(request);
            ZeroMemory(result);
            
            request.action = TRADE_ACTION_DEAL;
            request.symbol = _Symbol;
            request.volume = PositionGetDouble(POSITION_VOLUME);
            request.type = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 
                          ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            request.price = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ?
                           SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                           SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            request.deviation = 10;
            request.magic = 12346;
            request.comment = "BTC EOD Close";
            
            // Add proper error checking for OrderSend
            if(OrderSend(request, result))
            {
                if(result.retcode == TRADE_RETCODE_DONE)
                {
                    Print("BTC Position closed successfully. Ticket: ", tickets[i]);
                }
                else
                {
                    Print("BTC Position close failed. Ticket: ", tickets[i], ", Return code: ", result.retcode);
                }
            }
            else
            {
                Print("OrderSend failed when closing BTC position. Ticket: ", tickets[i], ", Error: ", GetLastError());
            }
        }
    }
}
