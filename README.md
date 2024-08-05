# Setup Instructions

1. **Install `sqlx` CLI**:  
   Ensure you have the `sqlx` CLI installed before proceeding. You can install it using the following command:
   
   ```sh
   cargo install sqlx-cli --no-default-features --features rustls,postgres
   ```

2. **Run the initialization script**:  
   This script will start the Docker containers, including PostgreSQL, Kafka, and other necessary services.
   ```sh
   ./startup.sh
   ```

3. **Perform Database Operations**:  
   Insert, update, or delete records in the database as needed.
   ```sh
   psql -h localhost -p 5433 -U postgres -d replic8 # you can connect to the db using psql
   ```
   ```sql
   INSERT INTO subscriptions (id, email, name, subscribed_at) \
   VALUES ('e3b0c442-98fc-462d-83e0-5c87a849f2e3', 'john.doe@example.com', 'John Doe', '2024-08-04 12:34:56'); # example 
   ```

4. **View Kafka Messages**:  
   Open Kafka UI in your browser to view the topics and messages. The UI is available at:
   ```sh
   http://localhost:8080
   ```
