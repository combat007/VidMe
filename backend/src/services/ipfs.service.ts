import fs from 'fs';
import pinata, { PINATA_GATEWAY } from '../config/pinata';

export interface UploadResult {
  cid: string;
  gatewayUrl: string;
}

export async function uploadToIPFS(filePath: string, fileName: string): Promise<UploadResult> {
  const readableStream = fs.createReadStream(filePath);

  const options = {
    pinataMetadata: {
      name: fileName,
    },
    pinataOptions: {
      cidVersion: 0 as const,
    },
  };

  const result = await pinata.pinFileToIPFS(readableStream, options);
  const cid = result.IpfsHash;

  return {
    cid,
    gatewayUrl: `${PINATA_GATEWAY}/${cid}`,
  };
}

export async function unpinFromIPFS(cid: string): Promise<void> {
  try {
    await pinata.unpin(cid);
  } catch (err) {
    console.error(`Failed to unpin CID ${cid}:`, err);
  }
}
