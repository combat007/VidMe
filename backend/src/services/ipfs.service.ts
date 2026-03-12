import fs from 'fs';
import path from 'path';
import { v4 as uuidv4 } from 'uuid';
import {
  S3Client,
  PutObjectCommand,
  DeleteObjectCommand,
  HeadObjectCommand,
  CopyObjectCommand,
} from '@aws-sdk/client-s3';

const FILEBASE_BUCKET = process.env.FILEBASE_BUCKET!;

const s3 = new S3Client({
  endpoint: 'https://s3.filebase.com',
  region: 'us-east-1',
  credentials: {
    accessKeyId: process.env.FILEBASE_KEY!,
    secretAccessKey: process.env.FILEBASE_SECRET!,
  },
  forcePathStyle: true,
});

export const IPFS_GATEWAY = 'https://ipfs.filebase.io/ipfs';

export interface UploadResult {
  cid: string;
  gatewayUrl: string;
}

export async function uploadToIPFS(filePath: string, fileName: string): Promise<UploadResult> {
  const ext = path.extname(fileName) || '';
  const tempKey = `temp-${uuidv4()}${ext}`;

  // Upload file to Filebase under a temp key
  await s3.send(new PutObjectCommand({
    Bucket: FILEBASE_BUCKET,
    Key: tempKey,
    Body: fs.createReadStream(filePath),
  }));

  // Filebase returns the IPFS CID in object metadata after upload
  const head = await s3.send(new HeadObjectCommand({
    Bucket: FILEBASE_BUCKET,
    Key: tempKey,
  }));

  const cid = head.Metadata?.['cid'];
  if (!cid) throw new Error('Filebase did not return a CID for the uploaded file');

  // Re-key the object using the CID so we can delete it by CID later
  await s3.send(new CopyObjectCommand({
    Bucket: FILEBASE_BUCKET,
    CopySource: `${FILEBASE_BUCKET}/${tempKey}`,
    Key: cid,
  }));
  await s3.send(new DeleteObjectCommand({ Bucket: FILEBASE_BUCKET, Key: tempKey }));

  return {
    cid,
    gatewayUrl: `${IPFS_GATEWAY}/${cid}`,
  };
}

export async function unpinFromIPFS(cid: string): Promise<void> {
  try {
    await s3.send(new DeleteObjectCommand({ Bucket: FILEBASE_BUCKET, Key: cid }));
  } catch (err) {
    console.error(`Failed to delete CID ${cid} from Filebase:`, err);
  }
}
