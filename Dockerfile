FROM klakegg/hugo:ext-ubuntu

EXPOSE 1313

RUN hugo new site myblog && cd myblog \
    && git clone https://github.com/dillonzq/LoveIt.git themes/LoveIt

WORKDIR myblog
COPY ./assets ./assets
COPY ./content ./content
COPY ./static ./static
COPY ./config.toml ./config.toml
CMD ["serve"]