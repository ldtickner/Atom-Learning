

<!-- Start of picture text -->
winge@<br><!-- End of picture text -->

# Data Engineer — Take-Home Task 

Atom Learning builds learning and assessment products for both families at home and teachers in schools. 

Our B2B platform, Quest, helps teachers understand how pupils are progressing against their own trajectory and the wider national population. It also uses predictive analytics to help teachers focus their time and attention where it can have the greatest impact on real-world outcomes. Almost everything behind those dashboards is a data modelling problem. This task is a small version of one. 

**Please spend no more than about two hours on this task.** We would rather see how you actually work than have you grind out something exhaustive. If you run out of time, tell us what you would have done next. 

What we are looking for: 

- **Structure** - what you build between the raw tables and the answer. 

- **Judgement** - this brief is intentionally broad and aligns with how a product manager may 

- request a feature. We want to understand how you reason through ambiguous problems. 

- **Clarity** - SQL and documentation someone else could pick up. 

We are not testing statistics or machine learning. A simple, well-reasoned answer beats a clever one that we can't follow. 

## Prerequisites 

You will have BigQuery access and your own dataset to build in. If you cannot get in, or anything here is unclear, contact the recruitment team. <u>https://console.cloud.google.com/bigquery?project=atom-analytics-candidates&p=atom-anal ytics-candidates&d=de_raw&page=dataset</u> 

This dataset is mock pupil activity data. Pupils sit assessments made up of questions. Every question belongs to a subject through a hierarchy of topics and subtopics. 

The dataset contains four tables: 

- **responses** - one row per question a pupil answered, including whether they got it right 

- **assessment_sittings** - one row per assessment a pupil sat 

- **pupils** - one row per pupil 

- **course_hierarchy** - one row per question, placing it in the subject hierarchy 

Interpret the tables as you find them. Where something is ambiguous, make a sensible call and write it down. We value the reasoning more than the result. 

The use of AI is encouraged - we use it heavily at Atom. Please include any LLM chat logs to show us how you’ve used AI. 

## The Task 

#### **Produce a SATs score for every pupil, in every subject, on an 80-120 scale.** 

#### **Step 1: Assign a SATs score based on their responses results** 

You can reference the <u>GOV UK</u> and external data to work out what a pupil's percentage on our assessments should correspond to on that scale. 

#### **Step 2: Implement a robust table design** 

Build it as something intended to last. Assume a colleague extends it next month to answer a different question and that it eventually runs at production volumes. You can expect the responses table to grow by >100m records in the near future. 

Things to consider when building the model(s): 

- It should be re-runnable. Running your models twice should produce the same result. 

- It should be point-in-time. We should be able to recompute a pupil's SATs score as it stood at a point in time. 

- The output table structure should be appropriate for migrating into our production application database. 

**Step 3** - Explain how you might predict a pupil's GCSE results from their primary-school work. Tell us what you would need to build that - what data, what assumptions and why. A few paragraphs is a complete answer. 

### Submission 

Push your work to a GitHub repository and send us the link. Please include: 

- Your SQL files 

- A README covering what you built, how the pieces fit together, data quality issues and the assumptions you've made 

- Your AI chat logs - /export from within Claude Code. 

- Materialise your models in your BigQuery dataset, so we can look at the output as well as the code. 

**If you need clarification or direction on any part of the task, please ask!** We're a collaborative team and asking questions is a normal part of how we work, so the same applies here. 

