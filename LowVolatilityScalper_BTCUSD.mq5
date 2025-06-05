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
input int CheckIntervalMinutes = 15;         // Check market every X minutes
input bool VerifyLowVolatility = true;       // Enable low volatility verification

input group "Trading Parameters"
input double LotSize = 0.001;                // Position size (smaller for BTC)
input int ProfitTargetPips = 50;             // Profit target in points
input int StopLossPips = 100;                // Stop loss in points
input int VolatilityPeriod = 60;             // Minutes to check volatility
input int VolatilityRange = 200;             // Maximum range in points (wider for BTC)

input group "Moving Average Settings"
input bool EnableMASignal = true;           // Enable Moving Average signals
input ENUM_MA_METHOD MAMethod = MODE_EMA;    // Moving Average method
input ENUM_TIMEFRAMES MATimeframe = PERIOD_M15; // Timeframe for MA calculation
input int MovingAverageCap = 60;             // MA Cap

input group "Risk Management"
input double MaxRiskPercent = 1.0;           // Maximum risk per trade (%)

input group "Trailing Stop Settings"
input double TrailingActivationPips = 25;   // Activate after X points profit
input double TrailingPercent = 69.69;        // Trail by % of profit

input group "Loss Management"
input bool EnableLossTimeLimit = true;      // Enable time-based loss exit
input int LossTimeLimitSeconds = 300;       // Close losing trades after X seconds (5 minutes default)

//--- Trailing Stop Statistics Structure
struct TrailStopStats {
    ulong ticket;               // Position ticket
    datetime openTime;          // Position open time
    datetime trailActivateTime; // Time when trailing stop activated
    bool trailActivated;        // Flag to track if trailing has been activated
    double initialProfit;       // Profit at activation time (points)
    bool lossTimeLimitChecked;  // Flag to track if loss time limit has been checked
};

//--- Global Variables
int dailyTradeCount = 0;
datetime lastCheckTime = 0;
datetime nextCheckTime = 0;
datetime currentDay = 0;
int currentMAPeriod = 50;                    // Current randomized MA period

// Trailing Stop Statistics Arrays
TrailStopStats positionStats[];
int statsCount = 0;

// Aggregated Statistics
int activatedPositions = 0;
double totalActivationMinutes = 0;
double minActivationMinutes = DBL_MAX;
double maxActivationMinutes = 0;

// Loss Time Limit Statistics
int positionsClosedByTimeLimit = 0;
double totalLossFromTimeLimit = 0;

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
    
    // Initialize random MA period
    RandomizeMA();
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                               |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    DisplayTrailingStats();
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
        
        // Display previous day's trailing stop statistics before reset
        if(activatedPositions > 0)
        {
            Print("=== END OF DAY TRAILING STOP SUMMARY ===");
            DisplayTrailingStats();
        }
        
        Print("New trading day started. Daily trade count reset.");
    }
}

//+------------------------------------------------------------------+
//| Schedule next market check                                       |
//+------------------------------------------------------------------+
void ScheduleNextCheck()
{
    // Fixed interval check every X minutes
    int minutesToNext = CheckIntervalMinutes;
    
    nextCheckTime = TimeCurrent() + (minutesToNext * 60);
    lastCheckTime = TimeCurrent();

    string nextCheckTimeStr = TimeToString(nextCheckTime, TIME_DATE|TIME_MINUTES);
    Print("Next market check scheduled at: ", nextCheckTimeStr, " (in ", minutesToNext, " minutes)");
    
    // Display trailing stop statistics every hour (every 4 checks if checking every 15 minutes)
    static int checkCounter = 0;
    checkCounter++;
    
    if(checkCounter % 4 == 0 && activatedPositions > 0)
    {
        DisplayCurrentSessionStats();
    }
}

//+------------------------------------------------------------------+
//| Randomize Moving Average period                                  |
//+------------------------------------------------------------------+
void RandomizeMA()
{
    // Generate random MA period between 1 and 60
    currentMAPeriod = 15 + (MathRand() % MovingAverageCap);
    Print("New random MA period selected: ", currentMAPeriod);
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
//| Preload Moving Average indicator data                           |
//+------------------------------------------------------------------+
bool PreloadIndicatorData()
{
    int maHandle = iMA(_Symbol, MATimeframe, currentMAPeriod, 0, MAMethod, PRICE_CLOSE);
    if(maHandle == INVALID_HANDLE)
    {
        Print("BTC Preload: Failed to create MA indicator with period ", currentMAPeriod);
        return false;
    }
    
    Print("BTC Preload: Created MA handle for period ", currentMAPeriod, ", attempting to load data...");
    
    // Wait for indicator calculation with multiple attempts
    int attempts = 0;
    int maxAttempts = 10;
    bool dataReady = false;
    
    while(attempts < maxAttempts && !dataReady)
    {
        attempts++;
        
        // Check if indicator is calculated
        int calculated = BarsCalculated(maHandle);
        if(calculated <= 0)
        {
            Print("BTC Preload: MA not calculated yet, attempt ", attempts, "/", maxAttempts);
            Sleep(MathRand() % 400 + 100); // Random delay 100-500ms
            continue;
        }
        
        // Check if we have enough bars
        int availableBars = iBars(_Symbol, MATimeframe);
        if(availableBars < currentMAPeriod + 2)
        {
            Print("BTC Preload: Insufficient bars. Need: ", currentMAPeriod + 2, ", Available: ", availableBars);
            Sleep(200);
            continue;
        }
        
        // Try to copy a small amount of data to test readiness
        double testValues[];
        ArraySetAsSeries(testValues, true);
        int copied = CopyBuffer(maHandle, 0, 0, 2, testValues);
        
        if(copied == 2 && testValues[0] != EMPTY_VALUE && testValues[0] > 0)
        {
            dataReady = true;
            Print("BTC Preload: MA data successfully loaded on attempt ", attempts, 
                  ". Current MA value: ", testValues[0], ", Calculated bars: ", calculated);
        }
        else
        {
            Print("BTC Preload: Data copy failed, attempt ", attempts, "/", maxAttempts, 
                  ". Copied: ", copied, ", Value: ", (copied > 0 ? testValues[0] : 0));
            Sleep(MathRand() % 400 + 100);
        }
    }
    
    // Clean up handle
    IndicatorRelease(maHandle);
    
    if(!dataReady)
    {
        Print("BTC Preload: Failed to load MA data after ", maxAttempts, " attempts");
        return false;
    }
    
    Print("BTC Preload: Moving Average data successfully preloaded for period ", currentMAPeriod);
    return true;
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
    
    // Randomize MA period for each check
    RandomizeMA();
    
    // Preload MA data if MA signal is enabled
    if(EnableMASignal)
    {
        if(!PreloadIndicatorData())
        {
            Print("BTC CheckMarket: Failed to preload MA data, proceeding with fallback");
        }
        else
        {
            Print("BTC CheckMarket: MA data successfully preloaded for period ", currentMAPeriod);
        }
    }
    
    // Check volatility conditions if enabled
    bool volatilityOK = true;
    if(VerifyLowVolatility)
    {
        volatilityOK = IsLowVolatilityPeriod();
        if(!volatilityOK)
        {
            Print("High volatility detected, skipping trade");
            return;
        }
    }
    
    // Get direction signal (MA or random fallback)
    int direction = 0;
    
    if(EnableMASignal)
    {
        direction = GetMASignal();
        if(direction == 0)
        {
            Print("No clear MA signal, using random direction as fallback");
            direction = (MathRand() % 2 == 0) ? 1 : -1; // Random 1 or -1
        }
    }
    else
    {
        // Use random direction when MA signal is disabled
        direction = (MathRand() % 2 == 0) ? 1 : -1;
        Print("MA signal disabled, using random direction: ", direction > 0 ? "LONG" : "SHORT");
    }
    
    if(direction != 0) // Should always be true now
    {
        bool isLong = (direction == 1);
        PlaceTrade(isLong);
        
        string volatilityMsg = VerifyLowVolatility ? "Low volatility confirmed. " : "Volatility check disabled. ";
        string signalSource = EnableMASignal ? "MA signal" : "Random signal";
        Print(volatilityMsg, signalSource, " (period ", currentMAPeriod, "): ", isLong ? "LONG" : "SHORT");
    }
}

//+------------------------------------------------------------------+
//| Check if current period has low volatility (optimized for BTC)  |
//+------------------------------------------------------------------+
bool IsLowVolatilityPeriod()
{
    double high = 0, low = DBL_MAX;
    int highIndex = -1, lowIndex = -1;

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
    
    // Calculate range in points (for BTC, we use _Point directly)
    double rangePoints = (high - low);
    
    Print("BTC Volatility Check - Range High: ", high, " (index ", highIndex, 
          "), Range Low: ", low, " (index ", lowIndex, "), Range Points: ", rangePoints);
    
    bool rangeAgeValid = (highIndex >= 3 && lowIndex >= 3);
    if(!rangeAgeValid)
    {
        Print("Range is too recent - high formed ", highIndex, " candles ago, low formed ", 
              lowIndex, " candles ago. Need at least 3 candles of distance.");
        return false;
    }


    // Check if range is within our volatility threshold
    if(rangePoints <= VolatilityRange)
    {
        // Calculate boundaries for middle 60% of the range
        double rangeWidth = high - low;
        double lowerBoundary = low + (rangeWidth * 0.24);  // 24% from bottom
        double upperBoundary = high - (rangeWidth * 0.24); // 24% from top
        double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         
        Print("BTC Middle Boundaries - Lower: ", lowerBoundary, ", Upper: ", upperBoundary, ", Current Price: ", currentPrice);
        
        // Check if price is within the middle 60%
        bool isWithinMiddlePercent = (currentPrice >= lowerBoundary && currentPrice <= upperBoundary);
        
        return isWithinMiddlePercent;
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
    double minDistance = MathMax(minStopLevel * point, 1 * point); // At least 50 points for BTC
    
    // Calculate stop loss and take profit distances  
    double slDistance = MathMax(StopLossPips * point, minDistance * 1); // Ensure SL is at least 2x min distance
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
          ", Min Distance: ", minDistance);
      // Send order
    if(OrderSend(request, result))
    {
        if(result.retcode == TRADE_RETCODE_DONE)
        {
            dailyTradeCount++;
              // Record position open time for trailing stop tracking
            ArrayResize(positionStats, statsCount + 1);
            positionStats[statsCount].ticket = result.order;
            positionStats[statsCount].openTime = TimeCurrent();
            positionStats[statsCount].trailActivated = false;
            positionStats[statsCount].initialProfit = 0;
            positionStats[statsCount].trailActivateTime = 0;
            positionStats[statsCount].lossTimeLimitChecked = false;
            statsCount++;
            
            Print("BTC Trade placed successfully. Direction: ", isLong ? "LONG" : "SHORT",
                  ", Price: ", price, ", SL: ", stopLoss, ", TP: ", takeProfit, 
                  ", Daily count: ", dailyTradeCount, ", Ticket: ", result.order);
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
    // Clean up statistics for closed positions
    CleanupClosedPositions();
    
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
                
                ulong ticket = PositionGetTicket(i);
                
                // Check loss time limit if enabled and position is losing
                if(EnableLossTimeLimit && profitPoints < 0)
                {
                    CheckLossTimeLimit(ticket, profitPoints);
                }                // Only apply trailing stop if we've reached activation threshold
                if(profitPoints >= TrailingActivationPips)
                {
                    ulong ticket = PositionGetTicket(i);
                    
                    // Check if this is the first activation for this position
                    for(int j = 0; j < statsCount; j++)
                    {
                        if(positionStats[j].ticket == ticket && !positionStats[j].trailActivated)
                        {
                            positionStats[j].trailActivated = true;
                            positionStats[j].trailActivateTime = TimeCurrent();
                            positionStats[j].initialProfit = profitPoints;
                            
                            // Calculate minutes until activation
                            double activationMinutes = (positionStats[j].trailActivateTime - positionStats[j].openTime) / 60.0;
                            
                            // Update statistics
                            activatedPositions++;
                            totalActivationMinutes += activationMinutes;
                            if(minActivationMinutes == DBL_MAX) minActivationMinutes = activationMinutes;
                            minActivationMinutes = MathMin(minActivationMinutes, activationMinutes);
                            maxActivationMinutes = MathMax(maxActivationMinutes, activationMinutes);
                            
                            Print("BTC Trailing stop ACTIVATED for position #", ticket, 
                                  " after ", NormalizeDouble(activationMinutes, 2), " minutes. Initial profit: ", 
                                  NormalizeDouble(profitPoints, 2), " points");
                            break;
                        }
                    }
                    
                    // Calculate trailing distance as percentage of profit
                    double trailingDistancePoints = profitPoints * (TrailingPercent / 100.0);
                    
                    // Ensure minimum trail distance of 5 points for BTC
                    if(trailingDistancePoints < 5.0) trailingDistancePoints = 5.0;
                    
                    double newSL;
                    bool modifyNeeded = false;
                    
                    if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                    {
                        // For buy positions, trail below the current price
                        newSL = openPrice + (profitPoints * (TrailingPercent / 100.0) * pointValue);
                        
                        // Only modify if the new SL is higher than the current one
                        if(newSL > currentSL)
                            modifyNeeded = true;
                    }
                    else
                    {
                        // For sell positions, trail above the current price
                        newSL = openPrice - (profitPoints * (TrailingPercent / 100.0) * pointValue);
                        
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

//+------------------------------------------------------------------+
//| Check if losing position should be closed due to time limit     |
//+------------------------------------------------------------------+
void CheckLossTimeLimit(ulong ticket, double profitPoints)
{
    // Find the position in our tracking array
    for(int i = 0; i < statsCount; i++)
    {
        if(positionStats[i].ticket == ticket)
        {            // Skip if already checked to avoid repeated messages
            if(positionStats[i].lossTimeLimitChecked)
                return;
                
            datetime currentTime = TimeCurrent();
            int secondsOpen = (int)(currentTime - positionStats[i].openTime);
            
            if(secondsOpen >= LossTimeLimitSeconds)
            {
                positionStats[i].lossTimeLimitChecked = true;
                  Print("BTC Loss Time Limit: Position #", ticket, 
                      " has been losing for ", secondsOpen, " seconds",
                      " (limit: ", LossTimeLimitSeconds, "s). Current loss: ", 
                      NormalizeDouble(profitPoints, 2), " points. Closing position...");
                  // Close the position
                if(ClosePositionByTicket(ticket))
                {
                    // Update loss time limit statistics
                    positionsClosedByTimeLimit++;
                    totalLossFromTimeLimit += MathAbs(profitPoints);
                    
                    Print("BTC Loss Time Limit: Position #", ticket, " closed successfully due to time limit.",
                          " Total closed by time limit: ", positionsClosedByTimeLimit);
                }
                else
                {
                    Print("BTC Loss Time Limit: Failed to close position #", ticket);
                }
            }
            break;
        }
    }
}

//+------------------------------------------------------------------+
//| Close a specific position by ticket                             |
//+------------------------------------------------------------------+
bool ClosePositionByTicket(ulong ticket)
{
    if(!PositionSelectByTicket(ticket))
    {
        Print("BTC Close: Position #", ticket, " not found");
        return false;
    }
    
    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);
    ZeroMemory(result);
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = PositionGetString(POSITION_SYMBOL);
    request.volume = PositionGetDouble(POSITION_VOLUME);
    request.type = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 
                  ORDER_TYPE_SELL : ORDER_TYPE_BUY;
    request.price = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ?
                   SymbolInfoDouble(request.symbol, SYMBOL_BID) :
                   SymbolInfoDouble(request.symbol, SYMBOL_ASK);
    request.deviation = 10;
    request.magic = 12346;
    request.comment = "BTC_LossTimeLimit";
    request.position = ticket;
    
    if(OrderSend(request, result))
    {
        if(result.retcode == TRADE_RETCODE_DONE)
        {
            return true;
        }
        else
        {
            Print("BTC Close: Failed to close position #", ticket, ". Return code: ", result.retcode);
            return false;
        }
    }
    else
    {
        Print("BTC Close: OrderSend failed for position #", ticket, ". Error: ", GetLastError());
        return false;
    }
}

//+------------------------------------------------------------------+
//| Get Moving Average Signal                                        |
//+------------------------------------------------------------------+
int GetMASignal()
{
    // Get Moving Average values
    double maValues[];
    ArraySetAsSeries(maValues, true);
    
    int maHandle = iMA(_Symbol, MATimeframe, currentMAPeriod, 0, MAMethod, PRICE_CLOSE);
    if(maHandle == INVALID_HANDLE)
    {
        Print("Failed to create Moving Average indicator with period ", currentMAPeriod);
        return 0; // No signal
    }
    
    // Wait for indicator to be ready and try multiple times
    int attempts = 0;
    int maxAttempts = 5;
    
    while(attempts < maxAttempts)
    {
        // Check if indicator is ready
        if(BarsCalculated(maHandle) <= 0)
        {
            Print("MA indicator not ready yet, attempt ", attempts + 1);
            Sleep(100); // Wait 100ms
            attempts++;
            continue;
        }
        
        // Ensure we have enough bars
        int bars = iBars(_Symbol, MATimeframe);
        if(bars < currentMAPeriod + 2)
        {
            Print("Not enough bars for MA calculation. Need: ", currentMAPeriod + 2, ", Have: ", bars);
            IndicatorRelease(maHandle);
            return 0;
        }
        
        // Try to copy the indicator values
        int copied = CopyBuffer(maHandle, 0, 0, 2, maValues);
        if(copied == 2)
        {
            // Success - we have the data
            break;
        }
        else
        {
            Print("Failed to copy MA data, attempt ", attempts + 1, ", copied: ", copied, ", error: ", GetLastError());
            Sleep(100);
            attempts++;
        }
    }
    
    // If we couldn't get the data after all attempts
    if(attempts >= maxAttempts)
    {
        Print("Failed to get MA data after ", maxAttempts, " attempts");
        IndicatorRelease(maHandle);
        return 0; // No signal
    }
    
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double currentMA = maValues[0];
    
    // Validate the MA value
    if(currentMA <= 0 || currentMA == EMPTY_VALUE)
    {
        Print("Invalid MA value: ", currentMA);
        IndicatorRelease(maHandle);
        return 0;
    }
    
    Print("BTC Moving Average (period ", currentMAPeriod, ") - MA Value: ", currentMA, ", Current Price: ", currentPrice);
    
    // Simple trend following signals
    if(currentPrice > currentMA)
    {
        Print("BTC MA signal: BUY (price above MA)");
        IndicatorRelease(maHandle);
        return 1; // Long signal
    }
    else if(currentPrice < currentMA)
    {
        Print("BTC MA signal: SELL (price below MA)");
        IndicatorRelease(maHandle);
        return -1; // Short signal
    }
    else
    {
        Print("BTC price exactly at MA, no clear signal");
        IndicatorRelease(maHandle);
        return 0; // No signal
    }
}

//+------------------------------------------------------------------+
//| Display Trailing Stop Activation Statistics                     |
//+------------------------------------------------------------------+
void DisplayTrailingStats()
{
    Print("===== TRAILING STOP ACTIVATION STATISTICS =====");
    
    if(activatedPositions > 0)
    {
        double avgActivationMinutes = totalActivationMinutes / activatedPositions;
        
        Print("Total positions with activated trailing stops: ", activatedPositions);
        Print("Average time until trailing stop activation: ", NormalizeDouble(avgActivationMinutes, 2), " minutes");
        Print("Minimum activation time: ", NormalizeDouble(minActivationMinutes, 2), " minutes");
        Print("Maximum activation time: ", NormalizeDouble(maxActivationMinutes, 2), " minutes");
        
        // Calculate additional statistics
        double totalHours = totalActivationMinutes / 60.0;
        Print("Total activation time across all positions: ", NormalizeDouble(totalHours, 2), " hours");
        Print("Average activation time in hours: ", NormalizeDouble(avgActivationMinutes / 60.0, 3), " hours");
        
        // Show breakdown by position
        Print("--- Individual Position Details ---");
        for(int i = 0; i < statsCount; i++)
        {
            if(positionStats[i].trailActivated)
            {
                double activationTime = (positionStats[i].trailActivateTime - positionStats[i].openTime) / 60.0;
                Print("Ticket #", positionStats[i].ticket, 
                      ": Activated after ", NormalizeDouble(activationTime, 2), " minutes",
                      " with ", NormalizeDouble(positionStats[i].initialProfit, 2), " points profit");
            }
        }
    }
    else
    {
        Print("No trailing stops were activated during this session.");
        Print("Total positions tracked: ", statsCount);
        
        // Show positions that didn't reach activation threshold
        int unactivatedCount = 0;
        for(int i = 0; i < statsCount; i++)
        {
            if(!positionStats[i].trailActivated)
                unactivatedCount++;
        }        Print("Positions that didn't reach trailing activation threshold: ", unactivatedCount);
    }
    
    // Display Loss Time Limit Statistics
    if(EnableLossTimeLimit)
    {
        Print("--- Loss Time Limit Statistics ---");
        Print("Positions closed due to time limit: ", positionsClosedByTimeLimit);
        if(positionsClosedByTimeLimit > 0)
        {
            double avgLossPerPosition = totalLossFromTimeLimit / positionsClosedByTimeLimit;
            Print("Total loss from time limit closures: ", NormalizeDouble(totalLossFromTimeLimit, 2), " points");
            Print("Average loss per time limit closure: ", NormalizeDouble(avgLossPerPosition, 2), " points");
        }
        Print("Time limit setting: ", LossTimeLimitSeconds, " seconds (", 
              NormalizeDouble(LossTimeLimitSeconds / 60.0, 1), " minutes)");
    }
    else
    {
        Print("Loss time limit feature is disabled.");
    }
    
    Print("==============================================");
}

//+------------------------------------------------------------------+
//| Display Current Session Statistics (Real-time Updates)          |
//+------------------------------------------------------------------+
void DisplayCurrentSessionStats()
{
    if(activatedPositions > 0)
    {
        double avgActivationMinutes = totalActivationMinutes / activatedPositions;
        
        Print("--- Current Session Trailing Stop Stats ---");
        Print("Activated positions: ", activatedPositions, 
              ", Avg activation time: ", NormalizeDouble(avgActivationMinutes, 2), " minutes");
        Print("Range: ", NormalizeDouble(minActivationMinutes, 2), " - ", 
              NormalizeDouble(maxActivationMinutes, 2), " minutes");
    }
}

//+------------------------------------------------------------------+
//| Clean up closed positions from statistics tracking              |
//+------------------------------------------------------------------+
void CleanupClosedPositions()
{
    // Remove statistics for positions that are no longer open
    for(int i = statsCount - 1; i >= 0; i--)
    {
        bool positionExists = false;
        
        // Check if position still exists
        for(int j = 0; j < PositionsTotal(); j++)
        {
            if(PositionSelectByTicket(PositionGetTicket(j)))
            {
                if(PositionGetTicket(j) == positionStats[i].ticket)
                {
                    positionExists = true;
                    break;
                }
            }
        }
        
        // If position doesn't exist, remove from tracking
        if(!positionExists)
        {
            // Shift array elements down
            for(int k = i; k < statsCount - 1; k++)
            {
                positionStats[k] = positionStats[k + 1];
            }
            statsCount--;
            ArrayResize(positionStats, statsCount);
        }
    }
}

//+------------------------------------------------------------------+
