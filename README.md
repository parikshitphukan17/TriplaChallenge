<div align="center">
   <img src="/img/logo.svg?raw=true" width=600 style="background-color:white;">
</div>

# Tripla Engineering: Take-Home Assignments

Welcome\! This repository contains the take-home assignments we use for our technical hiring process at Tripla. Each exercise is designed to give you a feel for the kind of challenges we work on every day.

## Frequently Asked Questions

### Which assignment should I work on?

Please do not work on all of them. Your hiring manager will send you a direct link to the specific assignment you should complete.

If you are unsure which one to work on, please contact our talent acquisition team before you begin.

### How do I submit my solution?

Please follow these steps to submit your work:

1.  **Create a new, public repository** on your personal GitHub or GitLab account.
2.  **Copy the assignment code** into your new repository. You can do this by cloning our repository and pushing it to your new one, or by downloading the code as a ZIP and committing it.
3.  **Email the link** to your personal repository to the person who sent you the assignment.

**Important:** Please **do not fork our repository or open a pull request**. We use pull requests to manage and update the assignments, not to review candidate submissions.

### Can I use an AI assistant or LLM to help with the assignment?

Up to you. Our goal is to see how you solve problems in a real-world setting. If LLMs are part of your standard workflow, you are welcome to use them.

However, please ensure you fully understand the code you submit. Regardless of how the code was generated, we expect you to be able to explain the implementation details, design choices, and logic in depth during the follow-up interview.

If you use an AI assistant, please document its usage in your `README.md`, including:
1.  Which parts of the solution were developed with AI assistance.
2.  A description of the tools and your workflow.

### What happens after I submit?

Once you submit, our engineering team will review your solution. We will always provide you with feedback on your submission. If your solution aligns well with the role, we will contact you to schedule a follow-up interview to walk through your code with you.

### I have an idea for a feature. Should I build it?

That's up to you. We intentionally leave the problems open-ended to see how you make product and engineering decisions.

However, the priority should always be a simple, robust, and well-tested solution to the core problem. If a new feature feels like it would take several hours or days to implement, it's likely out of scope and not essential.

### Is it okay to share my solution publicly?

Yes, absolutely. You put in the time, so you own the code. It's completely reasonable for you to keep your solution and use it as you see fit. The real value for us is in the process and the conversation around your submission.

### The assignment uses a specific language. Can I solve it in a different one?
We strongly prefer that you solve the assignment in the language provided.

The goal is to give you a realistic feel for the technology stack you would be working with at Tripla. We understand that you may not be immediately proficient in this specific language, and we do not expect syntax perfection. We are more interested in seeing how you adapt to a new environment.

Because of this, our review and the follow-up interview will focus on core engineering skills rather than language trivia. 

### The assignment uses specific libraries. Can I change them?
Yes, absolutely. It is up to you to choose the best tool for the job. Feel free to update, remove, or replace any of the included dependencies.

Just be prepared to discuss your thought process behind the decision. We are interested in knowing why you prefer one tool over another and how it impacts the quality or maintainability of your solution.

### The requirements seem ambiguous. What should I do?

That's often intentional\! We want to see how you handle ambiguity and make design choices when the path isn't perfectly clear.

Our preference is that you make a reasonable assumption, document it in your `README`, and move forward. There's no wrong answer in these situations. If you feel completely blocked, don't hesitate to email us, and we'll be happy to provide clarification.

### Why a take-home assignment?

This assignment is a practical way for us to see your problem-solving skills on a realistic challenge. It's also a chance for you to see the kind of work we do and decide if it's a good fit. We use your submission as the starting point for a technical conversation in our follow-up interview.

### How can I make my submission stand out?

We appreciate it when candidates go the extra mile to show their engineering depth, but we have seen past candidates shoot themselves in the foot by focusing on the wrong things. To do well, focus on the following core principles.

Write meaningful tests. At Tripla, we do not deploy code unless we are certain it works. Simply having a suite of automated tests is not enough. We want to see that you truly understand the problem by identifying implicit or ambiguous requirements and edge cases, then designing tests that uncover implementation issues.

Be intentional with your design. We want to see how you navigate the solution space. Before writing code, think through the trade-offs of different approaches and choose the one that best fits the constraints. Your solution should reflect a series of deliberate choices rather than the first idea that came to mind.

Production-ready does not mean FAANG-scale. You do not need to build a system that handles billions of requests. To us, production-ready means:

* Your code works, implements all requirements, and handles failures gracefully.
* You include structured logging, metrics, or traces.
* You chose the most straightforward path and avoided over-engineering.
* Your code is readable and follows established conventions in the existing codebase.
* You understand and can articulate the strengths and weaknesses of your implementation.

Keep a clean git history. Avoid submitting your work as a single, massive commit. We prefer to see a series of small, iterative commits that show how you logically built the solution over time. This helps us follow your thought process.

Include a helpful README. A great README makes it easy for us to review your work. Use it to showcase your reasoning, document how to run and test the code, and highlight any assumptions you made.

Code defensively. The real world is unreliable. Validate your inputs, handle failure states explicitly, and never assume that an external API will always return a successful response. Thinking about risks and mitigating them in code is a key trait we look for.

If you use AI tools, be careful. Historically, we have found that coding assistants perform poorly on these specific assignments. They often miss the nuance required to solve the problem correctly. Remember that you are responsible for every line of code you submit.
