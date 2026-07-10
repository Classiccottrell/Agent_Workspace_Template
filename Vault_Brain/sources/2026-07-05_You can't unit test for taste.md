---
title: "You can't unit test for taste"
source: "https://dev.karltryggvason.com/you-cant-unit-test-for-taste/?ref=sidebar"
author:
  - "Karl Tryggvason"
published: 2026-06-22
clipped: 2026-07-05
description: "I’m building In the Long Run where runners do virtual runs on famous routes around the world. The app tallies up your Strava mileage and plots your total distance as progress against country- or continent-spanning routes. The intention is to provide long-term inspiration and motivation; life is a marathon, not a sprint. You can have a bad month or season but still make progress on your virtual traversal of the world."
domain: "karltryggvason.com"
tags:
  - "source"
  - "clipping"
---
I’m building [*In the Long Run*](https://inthelongrun.app/) where runners do *virtual* runs on famous routes around the world. The app tallies up your Strava mileage and plots your total distance as progress against country- or continent-spanning routes. The intention is to provide long-term inspiration and motivation; life is a marathon, not a sprint. You can have a bad month or season but still make progress on your virtual traversal of the world.

The app shows your progress on interactive maps, which lets users do some exploring of their own. But I had long wanted to enrich the maps with interesting sights or historical sites. For routes I was familiar with I could build such lists myself but that doesn’t scale to routes spanning countries I am not familiar with. So I set out to find a data source for points of interest that I could build a pipeline off. Along the way I wrestled with taste and biases, and fought a hallucinating llm. I initially thought AI would be the feature, but it ended up merely in a supporting role alongside other signals and data processing mainstays.

## Dataset and toolset

[GeoNames](https://www.geonames.org/) was an obvious starting point, an extensive data source with locations, categories and links. The full data set can be downloaded and has a Creative Commons licence. So with my friend Claude I set about building a pipeline to go from the raw dumps to serving relevant points of interest to users of *In the Long Run*.

We used Python as the programming language (had good library support for the tasks at hand), stored processed data locally as Apache Parquet files and used DuckDB as the query layer.[^1] This was my first time using both Parquet and DuckDB but the ergonomics of both felt good and Claude introduced me to their features step by step (and most of the DuckDB work was SQL that I am very familiar with). In general I find adding one or two new tools or technologies to a project is the best way to learn. If the entire stack is new to you the learning curve will be too steep and it might put you off the project entirely. AI coding agents change this calculus somewhat, but even then I find having a handle on *most* of the technologies being used lets me steer the agent better and make informed decisions instead of blindly following its lead.

![Screenshot of the point of interest feature](https://dev.karltryggvason.com/you-cant-unit-test-for-taste/itlr-poi-screenshot.png)

Point of interest feature screenshot for a runner on Route 66 near Springfield, Illinois.

I built a project plan with Claude before starting the implementation, outlining the different steps of the pipeline and feature work. As we went along we then built a spec/plan for each step that we could iterate on as we learned more from earlier work. This also meant I could start new agent sessions for each milestone. Condensing results from the previous milestones into short context and instructions for the next step gets you faster and better responses (I find big contexts quickly degrade the quality of agent work).

## Notability and notable biases

To begin with we downloaded and unzipped all the [required files from Geonames](https://download.geonames.org/export/dump/) and set up gitignores for the data files as most are too large to be version controlled.

The first step of processing was joining the downloaded files on the relevant columns and filtering out rows that were not useful for our purposes. For instance we excluded administrative divisions: countries, states, regions etc. We also selected specific feature codes that we thought would be most interesting: parks, historic sites, castles, monuments, mountains, etc.[^2] Finally we added a population filter on populated places and an elevation filter on mountains. I’m sure this led to some false negatives, but we wanted a rough first draft.

Somewhat unintuitively the `alternateNames.txt` Geonames dataset includes Wikipedia links (where `isolanguage=link` and `alternate_name like %en.wikipedia.org%`, this usecase feels bolted on to their schema after the fact but it is very helpful data to have). We used this as a notoriety/relevance signal, and it also provided texts that we could build blurbs from as Wikipedia summaries also have a Creative Commons licence.

We built a basic sanity check for this pipeline step that helped us verify we weren’t skipping notable landmarks, this let us tweak some of the filtering. For instance, the first draft pulled in the Australian rural locality [Stonehenge](https://en.wikipedia.org/wiki/Stonehenge,_New_South_Wales) but not the prehistoric megalithic structure (its more famous namesake). When working in English you also want to make sure you pull in the relevant alternate names / languages and use the relevant Wikipedia URL as a cross reference (GeoNames stores the canonical name in the local language).

The final result of this step was a parquet file with around 725 thousand rows for points of interest globally. A significant reduction from the 13 million in the full original set we started out with.

![First pass candidate set by feature class](https://dev.karltryggvason.com/you-cant-unit-test-for-taste/candidates-by-class.png)

Populated places are the bulk of the Geonames dataset. But we don't want the points of interest to just show every town, village and hamlet on the way.

In the second step we matched all candidates from the first step with each of the [routes](https://inthelongrun.app/routes) we have. First we take a GeoJSON file for the route and build a bounding box to quickly filter to just the points remotely close to the route. We then iterate over the route coordinates to see which of the points inside the bounding box also fall within a given distance of the route itself (50km by default). We used Shapely and Pyproj for the geo calculations and to calculate a “ *distance along route* ” attribute so that we can decide “ *when* ” we should show the point of interest to the runner.

The output from this step is a route specific parquet file used for further refinement of the route. For our Iceland ring road route (1,321 km) we got 511 POIs, for the longest route in the app, Cape Town to Magadan (23,257 km) we got 10 thousand POIs while Route 66 (3,787 km) got 14,181 POIs. This was an early sign that our anglophone-Wikipedia signal was really a “ *where do English speakers live and edit wikis* ” bias.

## The LLM lies but it does have taste

In the third step we enriched the data we have with Wikipedia information and used an LLM to generate a rating for each point of interest. At first I’d also intended to use LLM generated summaries for the points of interest, but that proved a significant challenge with minor benefits.

First we fetch the Wikipedia summary for each of the points we have for a given route. We do the same for Wikidata, for each Wikipedia URL, look up how many language Wikipedias have an article on that subject. This is another good notoriety signal, if a page exists in many languages it is likely to be more significant than one that only has an entry in the English Wikipedia. The wiki data we can cache globally; this saves us a refetch in case later routes use the same points.

The wiki data is also input into an LLM powered step. We created a [tool](https://www.anthropic.com/engineering/advanced-tool-use) that we call to get structured data returned. Anthropic’s Haiku model was chosen for speed and price (unsurprisingly it was the one recommended through Claude Code by its “sibling” Opus) and [batched](https://platform.claude.com/docs/en/build-with-claude/batch-processing) the calls to get further price savings (50% off input and output tokens). This was my first time programmatically calling an LLM like this, the API made sense but its output wasn’t entirely consistent. For instance sometimes weird variants of the Anthropic Markup Language (antml) leaked into the tool call result string, calling for a cleanup. The batched tool calls can take hours to complete and the cost for the larger routes was around $10. I’d want to experiment with local or cheaper models here to see what the tradeoffs are.

Here we also caught some hallucinations, the first attempt did not “ground” the LLM enrichment in much data nor apply restrictions in the prompt. This meant that Haiku classified Central Park in [Decatur, Illinois](https://en.wikipedia.org/wiki/Decatur,_Illinois) as its more famous namesake in Manhattan and it got a large upgrade in its significance. For the second pass we added location and administrative metadata (country, city, etc) as input to the LLM as well as grounding it more carefully in the system prompt. Even then my spot checking uncovered several hallucinations, Haiku changed population sizes for towns and made mountains way larger than they really were (like Hugh Grant in that [90s classic](https://en.wikipedia.org/wiki/The_Englishman_Who_Went_up_a_Hill_but_Came_down_a_Mountain)).

I decided to just revert to the Wikipedia summaries at that point. The LLM text did often read better for our purposes, but correctness felt more important than readability.[^3] You could play around with the input data and prompts on the input side and build evals on the verification side, but ultimately it didn’t feel like it was worth the time or costs (LLM output tokens being more expensive than input). This challenge is an exciting one but tough to wrestle with outside of more easily verifiable domains like code (building integration tests to fact check text sounds like a Wittgensteinian task).

I still used the LLM to give the points of interest a rating used for calculating a significance score along with the feature codes and wiki language counts. Relying on just the Wikidata gave a lot of weight to every small town that had an automatically translated wiki page in 150 languages. Getting a more “ *subjective* ” rating from an LLM helped lift the more “interesting” points of interest for every route.

![Highest rated POIs so far](https://dev.karltryggvason.com/you-cant-unit-test-for-taste/poi-pipeline-sql.png)

Highest LLM rated points of interest so far. I suspect Reykjavík gets a 10 because it is explicitly mentioned in the prompt. It is a capital but is it more significant than Chicago or LA? How about Vatnajökull? I'm not sure.

So the LLM got relegated from writing (because it made stuff up) but promoted to offer the subjective taste latent in its weights. On the whole this step changed my thinking from this new technology being a foundation of the new feature (" *AI solves this* ") to AI just being a new tool in a bigger toolbox (" *AI nicely augments other traditional approaches* ").

As well as building the pipeline itself we built some tooling along the way to sanity check and debug the different stages. For instance a Leaflet based visualization tool to place the POIs on a map to verify placement and get a preview of what the end result would look like proved useful. I also built a `queries.sql` file to inspect the parquet files using [SQLYac](https://github.com/kalli/sqlyac) and DuckDB to spot check for false negatives or positives.

The last steps were to actually consume the artifacts produced by the pipeline, build the API endpoint for the data and show the points of interest to the user on the map. The implementation isn’t that relevant to the topic of the blog post but funnily enough this was also a step where Claude Code wanted to write the implementation first and was then going to give me the spec for approval. A shortcut that I’m sure many developers are familiar with, but an important place to try to rein in the AI and get it to follow the process you set out with.

## You can’t unit test for taste

From the enriched per-route candidates we then built an output artifact, a JSON file, that contained the points of interest for the route. This was the first point of interest data that was actually version controlled.

This is also where it became apparent that we would need per-route tweaks and parameters. Trying a few different routes I quickly realised that the data for every route is different, routes in different territories, countries and continents have different sights (cultural vs. natural vs. historical etc). This seems obvious when you say it out loud, but it didn’t really occur to me how big the variance was until we got this far.

For example, my native Iceland had a nice mix of nature, historical sites and populated places. But for other routes in more densely populated places the point of interest map basically became a population map, showing every town, village and hamlet along the way. Other points of interest were clustered in cities, because that is where the buildings, statues and monuments also are.

So we added per-route parameters like filtering on population, ranking based on Geoname feature classes, weighting the “ *subjective* ” LLM score higher against the “ *objectiveness* ” of the wiki link counts. We also applied a geographic filter so that only the most interesting sights in a given radius are shown to get a more even spread of points of interest between cities and the more rural paths that link them.

Overall the evaluation of success was one of the most challenging parts of the project. As a developer, I’m used to building features that either work or don’t and there is often an objective way to measure how well a feature performs. For messy real world data it was hard to evaluate how good or bad the pipeline was. Furthermore, it was easy to start optimising for a specific parameter or route and find later that this work led to severe degradations in other areas.

Verification becomes hard to reason about because there is no ground truth for points of interest, there are no red/green unit tests for taste. I’m sure these are familiar challenges to data scientists and that there are frameworks and evals for working on them. This will require more iteration and manual overrides. Hopefully with feedback and collaboration from the community. But for now I’ve shipped V1; you can try it out for select routes at [InTheLongRun.app](https://inthelongrun.app/)!

[^1]: This is my first time writing up a project that I worked on using an AI agent. I kept writing “ *we* ” because the project felt like a collaboration. At times, it even felt like I was being mentored by a senior because some of the technology was new to me. On reading it back, saying *we* feels like an accountability dodge, because of course I’m fully and solely responsible for any errors in this write-up or code. But just using *I/me* also feels dishonest, because so much of the implementation here isn’t fully mine so I feel like I’m taking too much credit for my collaboration with the machines. I figure this is a new kind of pronouns debate we’ll be having for the foreseeable future.

[^2]: Here I found the first agent hallucination of the project, Claude wanted to filter to the `NTMK` feature code. But as far as I can tell no such feature code exists and I can’t figure out what it was meant to be either.

[^3]: Of course Wikipedia can also be incorrect, but that feels like a more known failure model and at least there we have attribution.