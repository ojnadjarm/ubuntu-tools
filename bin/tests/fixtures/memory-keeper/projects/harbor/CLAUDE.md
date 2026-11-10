# Harbor portal (synthetic client project)
Admin page: https://portal.harbor-example.test/admin
Known fix: $DB->set_field('harbor_ticket', 'state', 2);
Way of working: run the full unit suite before every hand-off to the client.
