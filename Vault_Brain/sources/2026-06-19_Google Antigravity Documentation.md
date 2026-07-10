---
title: Google Antigravity Documentation
source: https://antigravity.google/docs/models
author:
  - google
published:
clipped: 2026-06-19
description: Learn how to use Google Antigravity
domain: antigravity.google
tags:
  - source
  - clipping
  - google
  - IDE
  - cli
---
## Models

## Reasoning Model

For the core reasoning model, Antigravity offers leading frontier models from the Gemini Enterprise Agent Platform:

Users can select which reasoning model they want to use within the model selector dropdown under the conversation prompt box:

![Model Selector Drop Down](https://antigravity.google/assets/image/docs/model-selector.png)

The choice of reasoning model is sticky between user messages within a conversation, so if you change the reasoning model while the Agent is running, it will continue to use the previously selected reasoning model until it has completed its steps for that user turn (or until you cancel the current execution).

Learn more about reasoning model rate limits in [our plans page](https://antigravity.google/docs/plans).

## Additional Models

Antigravity uses a number of other models for various parts of the stack that are not customizable:

- **Nano Banana 2**: Used by the generative image tool when the Agent wants to produce a UI mockup, needs images to populate a web page or application, generate system or architecture diagrams, or other generative image tasks.