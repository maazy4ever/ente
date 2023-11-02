export interface SRPAttributes {
    srpUserID: string;
    srpSalt: string;
    memLimit: number;
    opsLimit: number;
    kekSalt: string;
    isEmailMFAEnabled: boolean;
}

export interface GetSRPAttributesResponse {
    attributes: SRPAttributes;
}

export interface SRPSetupAttributes {
    srpSalt: string;
    srpVerifier: string;
    srpUserID: string;
    loginSubKey: string;
}

export interface SetupSRPRequest {
    srpUserID: string;
    srpSalt: string;
    srpVerifier: string;
    srpA: string;
}

export interface SetupSRPResponse {
    setupID: string;
    srpB: string;
}

export interface CompleteSRPSetupRequest {
    setupID: string;
    srpM1: string;
}

export interface CompleteSRPSetupResponse {
    setupID: string;
    srpM2: string;
}
