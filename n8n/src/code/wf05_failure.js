return $input.all().filter((i) => i.json.failed).map((i) => ({ json: i.json }));
