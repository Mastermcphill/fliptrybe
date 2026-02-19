FROM getmeili/meilisearch:v1.11

ENV MEILI_DB_PATH=/meili_data
ENV MEILI_HTTP_ADDR=0.0.0.0:7700

EXPOSE 7700

CMD ["meilisearch", "--http-addr", "0.0.0.0:7700", "--db-path", "/meili_data"]
