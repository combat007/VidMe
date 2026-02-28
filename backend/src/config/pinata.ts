import PinataSDK from '@pinata/sdk';

const pinata = new PinataSDK({
  pinataApiKey: process.env.PINATA_API_KEY!,
  pinataSecretApiKey: process.env.PINATA_API_SECRET!,
});

export const PINATA_GATEWAY = 'https://gateway.pinata.cloud/ipfs';

export default pinata;
