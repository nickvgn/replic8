use futures::StreamExt;
use serde::Deserialize;
use std::time::{SystemTime, UNIX_EPOCH};

use chrono::NaiveDateTime;
use dotenvy::dotenv;
use sqlx::{query_as, PgPool};
use tokio_postgres::{NoTls, SimpleQueryMessage};
use uuid::Uuid;

#[allow(dead_code)]
#[derive(Debug)]
struct Subscription {
    id: uuid::Uuid,
    email: String,
    name: String,
    subscribed_at: NaiveDateTime,
}

#[allow(dead_code)]
#[derive(Debug, Deserialize)]
struct Wal2JsonEvent {
    change: Vec<Change>,
}

#[allow(dead_code)]
#[derive(Debug, Deserialize)]
struct Change {
    kind: String,
    schema: String,
    table: String,
    columnnames: Option<Vec<String>>,
    columntypes: Option<Vec<String>>,
    columnvalues: Option<Vec<serde_json::Value>>,
    oldkeys: Option<OldKeys>,
}

#[allow(dead_code)]
#[derive(Debug, Deserialize)]
struct OldKeys {
    keynames: Vec<String>,
    keyvalues: Vec<serde_json::Value>,
}

#[tokio::main]
async fn main() {
    dotenv().ok();
    tracing_subscriber::fmt::init();

    let url = std::env::var("DATABASE_URL").expect("DATABASE_URL must be set");

    let pool = PgPool::connect(&url).await.expect("Failed to create pool");

    let uuid =
        Uuid::parse_str("47d16477-6464-41ad-b749-f27d757e46b0").expect("Failed to parse UUID");

    let test = query_as!(
        Subscription,
        r#" SELECT id, email, name, subscribed_at FROM subscriptions WHERE id = $1 "#,
        uuid
    )
    .fetch_one(&pool)
    .await
    .unwrap();

    println!("{:?}", test);

    let config = "host=localhost user=postgres password=password dbname=replic8 port=5433 replication=database";

    let (client, connection) = tokio_postgres::connect(config, NoTls)
        .await
        .expect("Failed to connect to the database");

    tokio::spawn(async move {
        if let Err(e) = connection.await {
            eprintln!("connection error: {}", e);
        }
    });

    //let slot_name = "slot";
    let slot_name = "slot_".to_owned()
        + &SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_millis()
            .to_string();
    let slot_query = format!(
        "CREATE_REPLICATION_SLOT {} TEMPORARY LOGICAL \"wal2json\"",
        slot_name
    );

    let lsn = client
        .simple_query(&slot_query)
        .await
        .unwrap()
        .into_iter()
        .filter_map(|msg| match msg {
            SimpleQueryMessage::Row(row) => Some(row),
            _ => None,
        })
        .collect::<Vec<_>>()
        .first()
        .unwrap()
        .get("consistent_point")
        .unwrap()
        .to_owned();

    let query = format!("START_REPLICATION SLOT {} LOGICAL {}", slot_name, lsn);

    let duplex_stream = client
        .copy_both_simple::<bytes::Bytes>(&query)
        .await
        .unwrap();

    let mut duplex_stream_pin = Box::pin(duplex_stream);

    loop {
        match duplex_stream_pin.as_mut().next().await {
            None => break,
            Some(Err(_)) => continue,
            // type: XLogData (WAL data, ie. change of data in db)
            Some(Ok(event)) if event[0] == b'w' => {
                // Skip the first byte which is the message type
                let wal_data = &event[1..];

                // Find the start of the JSON data
                if let Some(start_index) = wal_data.iter().position(|&b| b == b'{') {
                    let json_data = &wal_data[start_index..];

                    if let Ok(event_str) = std::str::from_utf8(json_data) {
                        match serde_json::from_str::<Wal2JsonEvent>(event_str) {
                            Ok(wal_event) => {
                                tracing::info!("WAL JSON data: {:#?}", wal_event);
                            }
                            Err(err) => {
                                tracing::error!("Failed to parse WAL event as JSON: {}", err);
                                tracing::error!("WAL event: {}", event_str);
                            }
                        }
                    } else {
                        tracing::error!("Failed to convert WAL event to string: {:?}", json_data);
                    }
                } else {
                    tracing::error!("Failed to find JSON data in WAL event");
                }
            }
            Some(Ok(_event)) => {
                // tracing::info!("idk {}", event);
            }
        }
    }
    // let lsn = client
    //       .simple_query(&slot_query)
    //       .await
    //       .unwrap()
    //       .into_iter()
    //       .filter_map(|msg| match msg {
    //           SimpleQueryMessage::Row(row) => Some(row),
    //           _ => None,
    //       })
    //       .collect::<Vec<_>>()
    //       .first()
    //       .unwrap()
    //       .get("consistent_point")
    //       .unwrap()
    //       .to_owned();

    // Start replication stream
    // sqlx::query("START_REPLICATION SLOT test_slot LOGICAL 0/0 (proto_version '1', publication_names 'subscription_publication');
    // ")
    //     .execute(&pool)
    //     .await
    //     .expect("Failed to start replication stream");
    // let (r, w) = pool.into_inner();
    // let mut reader = tokio::io::BufReader::new(r);
    // let mut writer = w;
    //
    // let mut buffer = String::new();
    // loop {
    //     buffer.clear();
    //     reader.read_line(&mut buffer).await.unwrap();
    //     if buffer.is_empty() {
    //         break;
    //     }
    //
    //     println!("Received: {}", buffer);
    //
    //     // Acknowledge receipt of data
    //     let lsn: String = buffer.split_whitespace().nth(1).unwrap().to_string();
    //     writer.write_all(format!("START_REPLICATION SLOT my_slot LOGICAL {}\n", lsn).as_bytes()).await.unwrap();
    // }
    //
    // let mut listener = PgListener::connect_with(&pool)
    //     .await
    //     .expect("Failed to connect to listener");
    //
    // tracing::info!("Connected to the database");
    //
    // // Start listening to the replication slot
    // listener
    //     .listen("test_slot")
    //     .await
    //     .expect("Failed to listen to slot");
    //
    // tracing::info!("Listening to the replication slot");
    //
    // loop {
    //     tracing::info!("Waiting for notification...");
    //
    //     let notification = listener
    //         .recv()
    //         .await
    //         .expect("Failed to receive notification");
    //
    //     // This is where you handle the replication message
    //     tracing::info!("Received notification: {:?}", notification.payload());
    //
    //     // Sleep for a while before the next iteration
    //     //sleep(Duration::from_secs(1)).await;
    // }
}
