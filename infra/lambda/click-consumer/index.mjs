/**
 * Click Consumer Lambda
 *
 * Triggered by SQS (batch size 100). Each message is a JSON click event:
 *   { code: "Aukyj", ts: 1727524800000, ip_hash: "...", referer: "..." }
 *
 * Writes a DynamoDB item per click with a 90-day TTL.
 * Failed items are returned in batchItemFailures so SQS retries only those
 * items (partial batch failure reporting).
 */

import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, BatchWriteCommand } from "@aws-sdk/lib-dynamodb";

const client = new DynamoDBClient({ region: process.env.REGION || "ap-south-1" });
const ddb = DynamoDBDocumentClient.from(client);
const TABLE = process.env.DYNAMODB_TABLE;
const TTL_DAYS = 90;

export async function handler(event) {
  const batchItemFailures = [];

  // Build DynamoDB write requests (max 25 per BatchWrite call)
  const writeRequests = [];

  for (const record of event.Records) {
    try {
      const body = JSON.parse(record.body);
      const ts = body.ts || Date.now();
      const expiresAt = Math.floor(ts / 1000) + TTL_DAYS * 86400;

      writeRequests.push({
        messageId: record.messageId,
        request: {
          PutRequest: {
            Item: {
              link_code: body.code,
              ts,
              expires_at: expiresAt,
              ip_hash:    body.ip_hash  || null,
              referer:    body.referer  || null,
              user_agent: body.ua       || null,
            },
          },
        },
      });
    } catch (e) {
      console.error("Failed to parse SQS record", record.messageId, e.message);
      batchItemFailures.push({ itemIdentifier: record.messageId });
    }
  }

  // Batch into groups of 25 (DynamoDB BatchWrite limit)
  for (let i = 0; i < writeRequests.length; i += 25) {
    const chunk = writeRequests.slice(i, i + 25);
    try {
      const result = await ddb.send(new BatchWriteCommand({
        RequestItems: {
          [TABLE]: chunk.map((r) => r.request),
        },
      }));

      // Any unprocessed items should be retried
      const unprocessed = result.UnprocessedItems?.[TABLE] || [];
      if (unprocessed.length > 0) {
        // Map back to message IDs to signal SQS to retry
        unprocessed.forEach((_, idx) => {
          const failed = chunk[idx];
          if (failed) batchItemFailures.push({ itemIdentifier: failed.messageId });
        });
      }
    } catch (e) {
      console.error("BatchWrite failed", e.message);
      // Mark all items in the chunk as failed
      chunk.forEach((r) => batchItemFailures.push({ itemIdentifier: r.messageId }));
    }
  }

  return { batchItemFailures };
}
