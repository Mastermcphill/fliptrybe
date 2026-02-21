FROM getmeili/meilisearch:v1.11

ENV MEILI_DB_PATH=/meili_data
ENV MEILI_HTTP_ADDR=0.0.0.0:7700
ENV MEILI_ENV=production

EXPOSE 7700

CMD ["sh", "-c", "if [ \"${MEILI_ENV}\" = \"production\" ] && [ -z \"${MEILI_MASTER_KEY}\" ]; then echo 'MEILI_MASTER_KEY is required when MEILI_ENV=production' >&2; exit 1; fi; exec meilisearch --http-addr \"${MEILI_HTTP_ADDR}\" --db-path \"${MEILI_DB_PATH}\""]
