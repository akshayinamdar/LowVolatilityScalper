//+------------------------------------------------------------------+
//|                                          LowVolatilityScalper.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

//--- Input Parameters
input group "Trading Limits"
input int MaxConcurrentTrades = 3;           // Maximum concurrent trades
input int MaxDailyTrades = 20;               // Maximum trades per day
input string DailyStartTime = "06:00";       // Daily start time (HH:MM)
input string DailyEndTime = "18:00";         // Daily end time (HH:MM)

input group "Market Checking Mechanism"
input int CheckFrequency = 1;                // Checks per hour
input bool RandomCheckWindow = true;         // Enable random check times
input int MinTimeBetweenChecks = 10;         // Min minutes between checks
input int MaxTimeBetweenChecks = 30;         // Max minutes between checks

input group "Trading Parameters"
input double LotSize = 0.01;                 // Position size
input int ProfitTargetPips = 2;              // Profit target in pips
input int StopLossPips = 10;                 // Stop loss in pips
input int VolatilityPeriod = 30;             // Minutes to check volatility
input int VolatilityRange = 15;              // Maximum range in pips

input group "Moving Average Settings"
input int MAPeriod = 50;                     // Moving Average period
input ENUM_MA_METHOD MAMethod = MODE_EMA;    // Moving Average method
input ENUM_TIMEFRAMES MATimeframe = PERIOD_M15; // Timeframe for MA calculation
input bool EnableMASignal = true;           // Enable moving average signals

input group "Risk Management"
input double MaxRiskPercent = 2.0;           // Maximum risk per trade (%)

input group "Trailing Stop Settings"
input int TrailingActivationPips = 2.0;       // Activate after X pips profit
input double TrailingPercent = 50.0;        // Trail by % of profit (50=half)

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
    Print("Low Volatility Scalper EA initialized");
    
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
    Print("Low Volatility Scalper EA deinitialized. Reason: ", reason);
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
        // Use moving average strategy instead of random
        if(EnableMASignal)
        {
            int direction = GetMASignal();
            if(direction != 0) // 0 = no signal, 1 = long, -1 = short
            {
                bool isLong = (direction == 1);
                PlaceTrade(isLong);
                Print("Low volatility detected. MA signal: ", isLong ? "LONG" : "SHORT");
            }
            else
            {
                Print("Low volatility detected but no clear MA signal");
            }
        }
        else
        {
            // Fallback to random direction if MA signal is disabled
            bool isLong = (MathRand() % 2 == 0);
            PlaceTrade(isLong);
            Print("Low volatility detected. Random direction selected: ", isLong ? "LONG" : "SHORT");
        }
    }
}

//+------------------------------------------------------------------+
//| Check if current period has low volatility                      |
//+------------------------------------------------------------------+
bool IsLowVolatilityPeriod()
{
    double high = 0, low = DBL_MAX;
    int highIndex = -1, lowIndex = -1;  // Track which candles formed the range
    
    // Get high and low for the last VolatilityPeriod minutes
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    int copied = CopyRates(_Symbol, PERIOD_M1, 0, VolatilityPeriod, rates);
    
    if(copied > 0)
    {
        for(int i = 0; i < copied; i++)
        {
            if(rates[i].high > high) 
            {
                high = rates[i].high;
                highIndex = i;  // Store index of candle with highest high
            }
            if(rates[i].low < low) 
            {
                low = rates[i].low;
                lowIndex = i;   // Store index of candle with lowest low
            }
        }
    }
      // Calculate range in pips
    double rangePips = (high - low) / _Point;
    if(_Digits == 5 || _Digits == 3) rangePips /= 10;
    
    Print("Volatility Check - Range High: ", high, " (index ", highIndex, 
          "), Range Low: ", low, " (index ", lowIndex, "), Range Pips: ", rangePips);
    
    // NEW CHECK: Verify range high/low formed at least 3 candles ago
    bool rangeAgeValid = (highIndex >= 3 && lowIndex >= 3);
    
    if(!rangeAgeValid)
    {
        Print("Range is too recent - high formed ", highIndex, " candles ago, low formed ", 
              lowIndex, " candles ago. Need at least 3 candles of distance.");
        return false;
    }
    
    // Check if range is within our volatility threshold
    if(rangePips <= VolatilityRange)
    {
        // Calculate boundaries for middle 60% of the range
        double rangeWidth = high - low;
        double lowerBoundary = low + (rangeWidth * 0.2);  // 20% from bottom
        double upperBoundary = high - (rangeWidth * 0.2); // 20% from top
        double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         
        Print("Middle 60% Boundaries - Lower: ", lowerBoundary, ", Upper: ", upperBoundary, ", Current Price: ", currentPrice);
        // Check if price is within the middle 60%
        bool isWithinMiddle60Percent = (currentPrice >= lowerBoundary && currentPrice <= upperBoundary);
        
        return isWithinMiddle60Percent;
    }
    
    return false;
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
    
    // Get symbol point and minimum stops
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    int minStopLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
    
    // Calculate stop loss and take profit
    double pipValue = _Point;
    if(_Digits == 5 || _Digits == 3) pipValue *= 10;
    
    // Ensure we have reasonable minimum distances
    double minDistance = MathMax(minStopLevel * point, 1 * pipValue); // At least 1 pip
    
    // Calculate stop loss and take profit distances  
    double slDistance = MathMax(StopLossPips * pipValue, minDistance * 2); // Ensure SL is at least 2x min distance
    double tpDistance = MathMax(ProfitTargetPips * pipValue, minDistance); // Ensure TP is at least min distance
    
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
    
    // Normalize prices
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
        Print("Trade cancelled - Invalid stop levels. Price: ", price, 
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
    request.deviation = 3;
    request.magic = 12345;    request.comment = "LowVolScalper";
    
    Print("Trade attempt - Direction: ", isLong ? "LONG" : "SHORT",
          ", Price: ", price, ", SL: ", stopLoss, ", TP: ", takeProfit,
          ", SL Distance: ", slDistanceCheck, ", TP Distance: ", tpDistanceCheck,
          ", Min Distance: ", minDistance);
    
    // Send order
    if(OrderSend(request, result))
    {        if(result.retcode == TRADE_RETCODE_DONE)
        {
            dailyTradeCount++;
            Print("Trade placed successfully. Direction: ", isLong ? "LONG" : "SHORT",
                  ", Price: ", price, ", SL: ", stopLoss, ", TP: ", takeProfit, 
                  ", Daily count: ", dailyTradeCount);
        }
        else
        {
            Print("Trade failed. Return code: ", result.retcode, " - ", result.comment);
        }
    }
    else
    {
        Print("OrderSend failed. Error: ", GetLastError());
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
            
            if(posSymbol == _Symbol && posMagic == 12345)
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
    // Check if we need to close positions at end of day
    if(!IsWithinTradingHours())
    {
        return;
    }
    
    // Always process trailing stops
    ManageTrailingStops();
}

//+------------------------------------------------------------------+
//| Manage trailing stops for all open positions                     |
//+------------------------------------------------------------------+
void ManageTrailingStops()
{
    double pipValue = _Point;
    if(_Digits == 5 || _Digits == 3) pipValue *= 10;
    
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionSelectByTicket(PositionGetTicket(i)))
        {
            string posSymbol = PositionGetString(POSITION_SYMBOL);
            ulong posMagic = PositionGetInteger(POSITION_MAGIC);
            
            // Only process our own positions on the current symbol
            if(posSymbol == _Symbol && posMagic == 12345)
            {
                double currentSL = PositionGetDouble(POSITION_SL);
                double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
                double currentPrice = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 
                                     SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                                     SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                
                // Calculate profit in pips
                double profitPips;
                if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                {
                    profitPips = (currentPrice - openPrice) / pipValue;
                }
                else
                {
                    profitPips = (openPrice - currentPrice) / pipValue;
                }
                  // Only apply trailing stop if we've reached activation threshold
                if(profitPips >= TrailingActivationPips)
                {
                    // Calculate trailing distance as percentage of profit
                    double trailingDistancePips = profitPips * (TrailingPercent / 100.0);
                    
                    // Ensure minimum trail distance of 1 pip
                    if(trailingDistancePips < 1.0) trailingDistancePips = 1.0;
                    
                    double newSL;
                    bool modifyNeeded = false;
                    
                    if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                    {
                        // For buy positions, trail at percentage of profit from entry price
                        newSL = openPrice + (profitPips * (TrailingPercent / 100.0) * pipValue);
                        
                        // Only modify if the new SL is higher than the current one
                        if(newSL > currentSL)
                            modifyNeeded = true;
                    }
                    else
                    {
                        // For sell positions, trail at percentage of profit from entry price
                        newSL = openPrice - (profitPips * (TrailingPercent / 100.0) * pipValue);
                        
                        // Only modify if the new SL is lower than the current one
                        if(newSL < currentSL || currentSL == 0)
                            modifyNeeded = true;
                    }
                    
                    // Update the stop loss if needed
                    if(modifyNeeded)
                    {
                        Print("Updating trailing stop for position #", PositionGetTicket(i), 
                              " Current profit: ", profitPips, " pips",
                              " Trail distance: ", trailingDistancePips, " pips");
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
            Print("Trailing stop updated for ticket #", ticket, " to ", newSL);
            return true;
        }
        else
        {
            Print("Failed to update trailing stop. Error code: ", result.retcode);
        }
    }
    else
    {
        Print("OrderSend failed. Error: ", GetLastError());
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Get Moving Average Signal                                        |
//+------------------------------------------------------------------+
int GetMASignal()
{
    // Get Moving Average values
    double maValues[];
    ArraySetAsSeries(maValues, true);
    
    int maHandle = iMA(_Symbol, MATimeframe, MAPeriod, 0, MAMethod, PRICE_CLOSE);
    if(maHandle == INVALID_HANDLE)
    {
        Print("Failed to create Moving Average indicator");
        return 0; // No signal
    }
    
    // Copy the indicator values
    if(CopyBuffer(maHandle, 0, 0, 2, maValues) < 2)
    {
        Print("Failed to copy Moving Average data");
        IndicatorRelease(maHandle);
        return 0; // No signal
    }
    
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double currentMA = maValues[0];
    
    Print("Moving Average - MA Value: ", currentMA, ", Current Price: ", currentPrice);
    
    // Simple trend following signals
    if(currentPrice > currentMA)
    {
        Print("MA signal: BUY (price above MA)");
        IndicatorRelease(maHandle);
        return 1; // Long signal
    }
    else if(currentPrice < currentMA)
    {
        Print("MA signal: SELL (price below MA)");
        IndicatorRelease(maHandle);
        return -1; // Short signal
    }
    else
    {
        Print("Price exactly at MA, no clear signal");
        IndicatorRelease(maHandle);
        return 0; // No signal
    }
}
