## Summary

This perl code drives Selenium. There is an ansible playbook that will help you get all of the dependencies setup on the server but it's best effort. You will likely ned to double check that everything was installed properly.

## Installation

Provide your pre-created mysql database credentials

    vi vars.yml

And execute the playbook

    ansible-playbook setup_playbook.yml
