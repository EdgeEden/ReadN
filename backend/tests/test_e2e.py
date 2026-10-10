import io
import pytest
from httpx import AsyncClient, ASGITransport
from app.main import app
from app.database import init_db


@pytest.mark.asyncio
async def test_full_backend_flow():
    await init_db()
    
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # 1. Health check
        res = await client.get("/api/health")
        assert res.status_code == 200
        assert res.json()["status"] == "healthy"

        # 2. Upload a minimal PDF
        # Minimal valid PDF file in bytes
        minimal_pdf = (
            b"%PDF-1.4\n"
            b"1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n"
            b"2 0 obj<</Type/Pages/Count 1/Kids[3 0 R]>>endobj\n"
            b"3 0 obj<</Type/Page/MediaBox[0 0 612 792]/Parent 2 0 R/Resources<<>>>>endobj\n"
            b"xref\n0 4\n0000000000 65535 f \n0000000009 00000 n \n0000000052 00000 n \n0000000101 00000 n \n"
            b"trailer<</Size 4/Root 1 0 R>>\nstartxref\n178\n%%EOF"
        )
        
        files = {
            "file": ("test_sample.pdf", io.BytesIO(minimal_pdf), "application/pdf")
        }
        res = await client.post("/api/documents/upload", files=files)
        assert res.status_code == 201
        doc_data = res.json()
        doc_id = doc_data["id"]
        assert doc_data["filename"] == "test_sample.pdf"
        assert doc_data["title"] == "test_sample"
        assert doc_data["file_size"] == len(minimal_pdf)

        # 3. List documents
        res = await client.get("/api/documents")
        assert res.status_code == 200
        docs = res.json()
        assert len(docs) >= 1
        assert any(d["id"] == doc_id for d in docs)

        # 4. Stream PDF file with Range request (HTTP 206 Partial Content)
        headers = {"Range": "bytes=0-10"}
        res = await client.get(f"/api/documents/{doc_id}/file", headers=headers)
        assert res.status_code == 206
        assert res.headers["content-range"].startswith("bytes 0-10/")
        assert len(res.content) == 11
        assert res.content == minimal_pdf[0:11]

        # 5. Create Annotation (Highlight)
        anno_payload = {
            "type": "highlight",
            "page_number": 1,
            "color_hex": "#FFE066",
            "rects": [{"x": 10.0, "y": 20.0, "width": 100.0, "height": 15.0}],
            "selected_text": "Sample Text",
            "note_content": "Important note"
        }
        res = await client.post(f"/api/documents/{doc_id}/annotations", json=anno_payload)
        assert res.status_code == 201
        anno_data = res.json()
        anno_id = anno_data["id"]
        assert anno_data["selected_text"] == "Sample Text"
        assert anno_data["note_content"] == "Important note"

        # 6. List annotations
        res = await client.get(f"/api/documents/{doc_id}/annotations")
        assert res.status_code == 200
        annos = res.json()
        assert len(annos) == 1
        assert annos[0]["id"] == anno_id

        # 7. Update annotation
        update_payload = {
            "color_hex": "#99E9F2",
            "note_content": "Updated note content"
        }
        res = await client.put(f"/api/documents/{doc_id}/annotations/{anno_id}", json=update_payload)
        assert res.status_code == 200
        updated = res.json()
        assert updated["color_hex"] == "#99E9F2"
        assert updated["note_content"] == "Updated note content"

        # 8. Batch Sync Annotations
        batch_payload = {
            "annotations": [
                {
                    "id": anno_id,
                    "type": "highlight",
                    "page_number": 1,
                    "color_hex": "#D0BFFF",
                    "rects": [{"x": 10.0, "y": 20.0, "width": 100.0, "height": 15.0}],
                    "selected_text": "Sample Text",
                    "note_content": "Batch updated"
                },
                {
                    "type": "note",
                    "page_number": 2,
                    "color_hex": "#FFC9C9",
                    "rects": [{"x": 30.0, "y": 40.0, "width": 80.0, "height": 12.0}],
                    "selected_text": "Second Quote",
                    "note_content": "Second note"
                }
            ]
        }
        res = await client.post(f"/api/documents/{doc_id}/annotations/batch", json=batch_payload)
        assert res.status_code == 200
        synced = res.json()
        assert len(synced) == 2

        # 9. Test OCR trigger and status polling
        ocr_res = await client.post(f"/api/documents/{doc_id}/ocr", json={"languages": "chi_sim+eng+equ"})
        assert ocr_res.status_code == 200
        ocr_data = ocr_res.json()
        assert ocr_data["doc_id"] == doc_id
        assert ocr_data["status"] in ["processing", "completed"]

        status_res = await client.get(f"/api/documents/{doc_id}/ocr-status")
        assert status_res.status_code == 200
        assert status_res.json()["doc_id"] == doc_id

        # 10. Test OCR Revert endpoint
        revert_res = await client.post(f"/api/documents/{doc_id}/ocr/revert", json={"page_scope": "all"})
        assert revert_res.status_code == 200
        reverted_doc = revert_res.json()
        assert reverted_doc["id"] == doc_id
        assert reverted_doc["ocr_status"] == "none"

        # 11. Test Document Image Upload & Download
        fake_png = b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15c4\x00\x00\x00\nIDATx\x9cc\x00\x01\x00\x00\x05\x00\x01\r\n-\xb4\x00\x00\x00\x00IEND\xaeB`\x82"
        img_files = {"file": ("test_img.png", io.BytesIO(fake_png), "image/png")}
        upload_img_res = await client.post(f"/api/documents/{doc_id}/images/test_img.png", files=img_files)
        assert upload_img_res.status_code == 200

        get_img_res = await client.get(f"/api/documents/{doc_id}/images/test_img.png")
        assert get_img_res.status_code == 200
        assert get_img_res.content == fake_png
        assert get_img_res.headers["content-type"] == "image/png"

        # 12. Clean up / Delete Document
        res = await client.delete(f"/api/documents/{doc_id}")
        assert res.status_code == 204

        # Verify Document 404 & Image 404
        res = await client.get(f"/api/documents/{doc_id}")
        assert res.status_code == 404
        res_img = await client.get(f"/api/documents/{doc_id}/images/test_img.png")
        assert res_img.status_code == 404

