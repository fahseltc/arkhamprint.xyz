# ArkhamPrint.XYZ
Hosted at https://arkhamprint.xyz/

This project is meant to help players of the Arkham Horror LCG game to print out proxies of cards at home.
It takes a URL to a deck at [arkhambd.com](https://arkhamdb.com/) and generates a basic PDF with 9 cards on it.


## Technical Details
Uses Ruby 3.3.2 and Rails 8.0.2
Hosted on [Render](https://render.com/) Free-Tier
- This means that there can be some initial startup time of the instance after being idle for some time. 

Processing and generating a ~30 card deck often takes nearly 30 seconds and may time out in some circumstances.
This could be fixed with a background job system, but that would also add a lot of complexity.

## Code formatting
run `rubocop -a` to auto-format the code.