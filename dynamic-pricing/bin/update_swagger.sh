#!/bin/bash
# Exit on error
set -e

# Change directory to the script's parent root (dynamic-pricing directory)
cd "$(dirname "$0")/.."

echo "====================================================================="
echo "Generating OpenAPI Swagger Specification via Rswag"
echo "====================================================================="

# Check if we are running inside the Docker container
if [ -f /.dockerenv ] || [ -f /rails/Gemfile ]; then
  echo "Detected execution INSIDE the Docker container..."
  env RAILS_ENV=test bundle exec rails rswag:specs:swaggerize
else
  echo "Detected execution ON the Host machine. Delegating to Docker Compose..."
  docker compose exec -e RAILS_ENV=test interview-dev bundle exec rails rswag:specs:swaggerize
fi

echo "Post-processing generated OpenAPI spec to clean up multiple named examples..."
if [ -f /.dockerenv ] || [ -f /rails/Gemfile ]; then
  bundle exec ruby -e "
    require 'yaml'
    file = 'swagger/v1/swagger.yaml'
    if File.exist?(file)
      data = YAML.load_file(file)
      resp_200 = data.dig('paths', '/api/v1/pricing', 'get', 'responses', '200', 'content', 'application/json')
      if resp_200 && resp_200['examples'] && resp_200['examples']['example_0']
        nested = resp_200['examples']['example_0']['value']
        resp_200['examples'] = nested
        File.write(file, YAML.dump(data))
        puts 'Successfully formatted OpenAPI 3.0 named examples!'
      end
    end
  "
else
  docker compose exec -T interview-dev bundle exec ruby -e "
    require 'yaml'
    file = 'swagger/v1/swagger.yaml'
    if File.exist?(file)
      data = YAML.load_file(file)
      resp_200 = data.dig('paths', '/api/v1/pricing', 'get', 'responses', '200', 'content', 'application/json')
      if resp_200 && resp_200['examples'] && resp_200['examples']['example_0']
        nested = resp_200['examples']['example_0']['value']
        resp_200['examples'] = nested
        File.write(file, YAML.dump(data))
        puts 'Successfully formatted OpenAPI 3.0 named examples!'
      end
    end
  "
fi

echo "====================================================================="
echo "Swagger Specification generated successfully!"
echo "You can view the interactive documentation at http://localhost:3000/api-docs"
echo "====================================================================="
