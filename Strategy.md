# Low Volatility Random Direction Scalping Strategy

## Strategy Overview
A random-direction scalping approach designed to exploit low volatility periods in forex markets with quick 1-2 pip profits using random entry direction.

## Entry Conditions
1. **Trading Hours Check**: Verify current time is within daily start and end times
2. **Market Check Schedule**: Only analyze market at designated random check times
3. **Volatility Check**: Price must be ranging within a 15 pip range for the last 30 minutes
4. **Position Check**: Current price must be somewhere in the middle of this 15 pip range
5. **Market State**: Confirm we are in a genuine ranging/consolidation period
6. **Trade Direction**: Randomly select long or short (50% probability each)
7. **Trade Limits**: Must not exceed maximum concurrent trades or daily trade limits

## Position Management
- **Profit Target**: 1-2 pips
- **Stop Loss**: 10 pips
- **Position Size**: To be determined based on account size and risk tolerance
- **Trade Direction**: Random (50% buy, 50% sell) - no directional bias

## Input Parameters

### Trading Limits
- **Max Concurrent Trades**: Maximum number of open positions at any time
- **Max Daily Trades**: Maximum number of trades allowed per day
- **Daily Start Time**: Time to begin trading (e.g., 08:00)
- **Daily End Time**: Time to stop opening new trades (e.g., 18:00)

### Market Checking Mechanism
- **Check Frequency**: Number of times per hour/day to check market conditions
- **Random Check Window**: Enable/disable randomization of market check times
- **Min Time Between Checks**: Minimum minutes between consecutive market checks
- **Max Time Between Checks**: Maximum minutes between consecutive market checks

## Exit Rules
- **Take Profit**: Close position immediately when 1-2 pip profit is achieved
- **Stop Loss**: Close position if price moves 10 pips against the entry
- **Time-based**: No specific time exit for now (simplest version)
- **End of Day**: Close all positions at daily end time

## Risk Parameters
- **Risk-Reward Ratio**: 1:5 to 1:10 (risking 10 pips to make 1-2 pips)
- **Required Win Rate**: Approximately 90%+ to be profitable after costs (challenging with random direction)
- **Position Limits**: Controlled by max concurrent trades parameter

## Implementation Notes
- Strategy uses random entry direction (no predictive element)
- Random market checking reduces system resource requirements and may help avoid overtrading
- Requires very precise execution and low-latency platform
- Transaction costs (spread + commission) are critical factor
- Best suited for major currency pairs with tight spreads
- Avoid trading during news events or high volatility periods
- Must respect daily trading hours and position limits
- Implementation can use scheduled tasks with random intervals between min/max check times

## Backtesting Requirements
- Test on historical 1-minute data
- Include realistic spread costs in calculations
- Measure actual win rate and average profit/loss per trade
- Validate 30-minute volatility detection algorithm
- Test with various parameter combinations for concurrent/daily trade limits