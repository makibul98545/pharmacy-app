import os
import pickle
from google.auth.transport.requests import Request
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload

# If modifying scopes, delete token.json once
SCOPES = ['https://www.googleapis.com/auth/drive.file']

BASE_DIR = os.path.abspath(os.path.dirname(__file__))
TOKEN_PATH = os.path.join(BASE_DIR, 'token.pickle')
CREDENTIALS_PATH = os.path.join(BASE_DIR, 'credentials.json')


def get_drive_service():
    creds = None

    # 🔥 LOAD TOKEN (no login)
    if os.path.exists(TOKEN_PATH):
        with open(TOKEN_PATH, 'rb') as token:
            creds = pickle.load(token)

    # 🔁 REFRESH OR LOGIN
    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
        else:
            flow = InstalledAppFlow.from_client_secrets_file(
                CREDENTIALS_PATH, SCOPES
            )
            creds = flow.run_local_server(port=8080, open_browser=True)

        # 💾 SAVE TOKEN (IMPORTANT)
        with open(TOKEN_PATH, 'wb') as token:
            pickle.dump(creds, token)

    return build('drive', 'v3', credentials=creds)


def upload_backup_to_drive(file_path):

    try:
        service = get_drive_service()

        from googleapiclient.http import MediaFileUpload

        file_metadata = {
            'name': os.path.basename(file_path)
        }

        media = MediaFileUpload(file_path, resumable=True)

        file = service.files().create(
            body=file_metadata,
            media_body=media,
            fields='id'
        ).execute()

        print("UPLOAD SUCCESS:", file.get('id'))

        return True

    except Exception as e:
        import traceback
        print("UPLOAD FAILED:")
        traceback.print_exc()
        return False